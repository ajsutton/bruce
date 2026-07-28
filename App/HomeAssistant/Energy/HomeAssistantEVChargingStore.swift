import Foundation

@MainActor
final class HomeAssistantEVChargingStore: ObservableObject {
  @Published private(set) var mode: HomeAssistantEVChargingMode?
  @Published private(set) var isLoading = false
  @Published private(set) var isLive = false
  @Published private(set) var isChanging = false
  @Published private(set) var showsProgress = false
  @Published private(set) var problem: Problem?

  private let client: any HomeAssistantEVCharging
  private let onAuthenticationRequired: @MainActor @Sendable () -> Void
  private let progressDelay: Duration
  private let updateTimeout: Duration
  private let progressSleep: @Sendable (Duration) async -> Void
  private let timeoutSleep: @Sendable (Duration) async -> Void
  private var operationGeneration = UUID()
  private var progressTask: Task<Void, Never>?
  private var updateTimeoutTask: Task<Void, Never>?
  private var modeChangeTask: Task<Void, Never>?
  private var lateReconciliationTask: Task<Void, Never>?
  private var modeChangeWaiter: CheckedContinuation<Void, Never>?
  private var rollbackMode: HomeAssistantEVChargingMode?
  private var lateModeChangesToReconcile: Set<UUID> = []
  private var canReconcileLateModeChanges = false
  private var needsLateModeChangeReconciliation = false

  init(
    client: any HomeAssistantEVCharging,
    mode: HomeAssistantEVChargingMode? = nil,
    progressDelay: Duration = .milliseconds(500),
    updateTimeout: Duration = .seconds(8),
    progressSleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    },
    timeoutSleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    },
    onAuthenticationRequired: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.client = client
    self.mode = mode
    isLive = mode != nil
    self.progressDelay = progressDelay
    self.updateTimeout = updateTimeout
    self.progressSleep = progressSleep
    self.timeoutSleep = timeoutSleep
    self.onAuthenticationRequired = onAuthenticationRequired
    canReconcileLateModeChanges = mode != nil
  }

  deinit {
    progressTask?.cancel()
    updateTimeoutTask?.cancel()
    modeChangeTask?.cancel()
    lateReconciliationTask?.cancel()
  }

  var canSelectMode: Bool {
    isLive && !isLoading && !isChanging
  }

  func load() async {
    await load(preservingProblem: false)
  }

  private func load(preservingProblem: Bool) async {
    guard !isChanging else { return }
    let generation = UUID()
    operationGeneration = generation
    canReconcileLateModeChanges = true
    isLoading = true
    isLive = mode != nil
    if !preservingProblem {
      problem = nil
    }
    scheduleProgress(for: generation)

    do {
      let loadedMode = try await client.loadEVChargingMode()
      try Task.checkCancellation()
      guard operationGeneration == generation else { return }
      mode = loadedMode
      isLoading = false
      isLive = true
      finishProgress()
    } catch is CancellationError {
      guard operationGeneration == generation else { return }
      isLoading = false
      isLive = false
      finishProgress()
    } catch {
      guard operationGeneration == generation else { return }
      guard !Task.isCancelled, !Self.isCancellation(error) else {
        isLoading = false
        isLive = false
        finishProgress()
        return
      }
      let loadProblem = Self.problem(for: error, operation: .loading)
      if !preservingProblem || loadProblem == .signInRequired {
        problem = loadProblem
      }
      isLoading = false
      isLive = false
      finishProgress()
      if loadProblem == .signInRequired {
        onAuthenticationRequired()
      }
    }
  }

  func selectMode(_ requestedMode: HomeAssistantEVChargingMode) async {
    guard canSelectMode, requestedMode != mode else { return }
    let previousMode = mode
    let generation = UUID()
    operationGeneration = generation
    rollbackMode = previousMode
    canReconcileLateModeChanges = true
    mode = requestedMode
    isChanging = true
    problem = nil
    scheduleProgress(for: generation)
    scheduleUpdateTimeout(
      for: generation,
      previousMode: previousMode
    )
    startModeChangeRequest(requestedMode, generation: generation)
    await waitForModeChange(generation: generation)
  }

  func markConnectionInProgress() {
    invalidateModeChange()
    operationGeneration = UUID()
    isLoading = true
    isLive = false
    finishProgress()
    problem = nil
  }

  func markConnectionUnavailable() {
    invalidateModeChange()
    operationGeneration = UUID()
    isLoading = false
    isLive = false
    finishProgress()
    if problem != .signInRequired {
      problem = .connectionNeedsManagement
    }
  }

  func reset() {
    invalidateModeChange()
    operationGeneration = UUID()
    mode = nil
    isLoading = false
    isLive = false
    finishProgress()
    problem = nil
  }
}

extension HomeAssistantEVChargingStore {
  private func startModeChangeRequest(
    _ requestedMode: HomeAssistantEVChargingMode,
    generation: UUID
  ) {
    modeChangeTask?.cancel()
    modeChangeTask = Task { [weak self, client] in
      let result: Result<HomeAssistantEVChargingMode, any Error>
      do {
        result = .success(try await client.setEVChargingMode(requestedMode))
      } catch {
        result = .failure(error)
      }
      self?.receiveModeChangeResult(
        result,
        requestedMode: requestedMode,
        generation: generation
      )
    }
  }

  private func waitForModeChange(generation: UUID) async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard operationGeneration == generation, isChanging else {
          continuation.resume()
          return
        }
        modeChangeWaiter = continuation
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.cancelModeChange(generation: generation)
      }
    }
  }

  private func receiveModeChangeResult(
    _ result: Result<HomeAssistantEVChargingMode, any Error>,
    requestedMode: HomeAssistantEVChargingMode,
    generation: UUID
  ) {
    if lateModeChangesToReconcile.remove(generation) != nil {
      reconcileLateModeChange()
      return
    }
    guard operationGeneration == generation, isChanging else { return }
    modeChangeTask = nil
    switch result {
    case .success(let confirmedMode):
      completeModeChange(confirmedMode, requestedMode: requestedMode)
    case .failure(let error):
      failModeChange(error)
    }
    performDeferredLateModeChangeReconciliation()
  }

  private func scheduleProgress(for generation: UUID) {
    finishProgress()
    progressTask = Task { [weak self, progressDelay, progressSleep] in
      await progressSleep(progressDelay)
      guard !Task.isCancelled else { return }
      guard let self, self.operationGeneration == generation else { return }
      self.showsProgress = true
    }
  }

  private func finishProgress() {
    progressTask?.cancel()
    progressTask = nil
    showsProgress = false
  }

  private func completeModeChange(
    _ confirmedMode: HomeAssistantEVChargingMode,
    requestedMode: HomeAssistantEVChargingMode
  ) {
    mode = confirmedMode
    isChanging = false
    isLive = true
    finishModeChange()
    if confirmedMode != requestedMode {
      problem = .updateFailed
    }
  }

  private func cancelModeChange(generation: UUID) {
    guard operationGeneration == generation, isChanging else { return }
    lateModeChangesToReconcile.insert(generation)
    operationGeneration = UUID()
    modeChangeTask?.cancel()
    modeChangeTask = nil
    rollBackModeChange()
  }

  private func failModeChange(_ error: any Error) {
    guard !Task.isCancelled, !Self.isCancellation(error) else {
      rollBackModeChange()
      reconcileLateModeChange()
      return
    }
    let controlProblem = Self.problem(for: error, operation: .changing)
    rollBackModeChange()
    problem = controlProblem
    if controlProblem == .signInRequired {
      onAuthenticationRequired()
    }
  }

  private func rollBackModeChange() {
    mode = rollbackMode
    isChanging = false
    isLive = false
    finishModeChange()
  }

  private func finishModeChange() {
    finishProgress()
    finishUpdateTimeout()
    rollbackMode = nil
    let waiter = modeChangeWaiter
    modeChangeWaiter = nil
    waiter?.resume()
  }

  private func invalidateModeChange() {
    if isChanging {
      mode = rollbackMode
    }
    modeChangeTask?.cancel()
    modeChangeTask = nil
    isChanging = false
    finishModeChange()
    lateModeChangesToReconcile = []
    canReconcileLateModeChanges = false
    needsLateModeChangeReconciliation = false
    lateReconciliationTask?.cancel()
    lateReconciliationTask = nil
  }

  private func scheduleUpdateTimeout(
    for generation: UUID,
    previousMode: HomeAssistantEVChargingMode?
  ) {
    finishUpdateTimeout()
    updateTimeoutTask = Task { [weak self, updateTimeout, timeoutSleep] in
      await timeoutSleep(updateTimeout)
      guard !Task.isCancelled else { return }
      guard let self, self.operationGeneration == generation, self.isChanging else { return }
      self.lateModeChangesToReconcile.insert(generation)
      self.operationGeneration = UUID()
      self.modeChangeTask?.cancel()
      self.modeChangeTask = nil
      self.mode = previousMode
      self.isChanging = false
      self.isLive = false
      self.problem = .updateTimedOut
      self.finishProgress()
      self.updateTimeoutTask = nil
      self.rollbackMode = nil
      let waiter = self.modeChangeWaiter
      self.modeChangeWaiter = nil
      waiter?.resume()
      self.performDeferredLateModeChangeReconciliation()
    }
  }

  private func finishUpdateTimeout() {
    updateTimeoutTask?.cancel()
    updateTimeoutTask = nil
  }

  private func reconcileLateModeChange() {
    guard canReconcileLateModeChanges else { return }
    guard !isChanging else {
      needsLateModeChangeReconciliation = true
      return
    }
    lateReconciliationTask?.cancel()
    let generation = UUID()
    operationGeneration = generation
    isLoading = true
    isLive = mode != nil
    scheduleProgress(for: generation)
    lateReconciliationTask = Task { [weak self, client] in
      let result: Result<HomeAssistantEVChargingMode, any Error>
      do {
        result = .success(try await client.loadEVChargingMode())
      } catch {
        result = .failure(error)
      }
      guard !Task.isCancelled else { return }
      self?.receiveLateReconciliationResult(result, generation: generation)
    }
  }

  private func receiveLateReconciliationResult(
    _ result: Result<HomeAssistantEVChargingMode, any Error>,
    generation: UUID
  ) {
    guard operationGeneration == generation else { return }
    lateReconciliationTask = nil
    switch result {
    case .success(let loadedMode):
      mode = loadedMode
      isLoading = false
      isLive = true
      finishProgress()
    case .failure(let error):
      isLoading = false
      isLive = false
      finishProgress()
      let loadProblem = Self.problem(for: error, operation: .loading)
      if problem == nil || loadProblem == .signInRequired {
        problem = loadProblem
      }
      if loadProblem == .signInRequired {
        onAuthenticationRequired()
      }
    }
  }

  private func performDeferredLateModeChangeReconciliation() {
    guard needsLateModeChangeReconciliation else { return }
    needsLateModeChangeReconciliation = false
    reconcileLateModeChange()
  }
}

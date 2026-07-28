import Foundation

@MainActor
final class HomeAssistantEVChargingStore: ObservableObject {
  @Published private(set) var mode: HomeAssistantEVChargingMode?
  @Published private(set) var activity: HomeAssistantEVChargingActivity
  @Published private(set) var isActivityLive: Bool
  @Published private(set) var isLoading = false
  @Published private(set) var isLive = false
  @Published private(set) var isRefreshing = false
  @Published private(set) var isChanging = false
  @Published private(set) var showsProgress = false
  @Published private(set) var problem: Problem?
  private let client: any HomeAssistantEVCharging
  private let onAuthenticationRequired: @MainActor @Sendable () -> Void
  private let progressDelay, updateTimeout: Duration
  private let progressSleep, timeoutSleep: @Sendable (Duration) async -> Void
  private let liveSubscription: HomeAssistantEVChargingLiveSubscription
  private let tasks = HomeAssistantEVChargingTasks()
  private var operationGeneration = UUID()
  private var rollbackMode: HomeAssistantEVChargingMode?
  private var lateReconciliationSubscriptionRevision = 0
  private var lateModeChangesToReconcile: Set<UUID> = []
  private var canReconcileLateModeChanges = false, needsLateModeChangeReconciliation = false
  init(
    client: any HomeAssistantEVCharging,
    mode: HomeAssistantEVChargingMode? = nil,
    activity: HomeAssistantEVChargingActivity = .unavailable,
    progressDelay: Duration = .milliseconds(500),
    updateTimeout: Duration = .seconds(8),
    progressSleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    },
    timeoutSleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
    onAuthenticationRequired: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.client = client
    self.mode = mode
    self.activity = activity
    isActivityLive = mode != nil && activity != .unavailable
    isLive = mode != nil
    self.progressDelay = progressDelay
    self.updateTimeout = updateTimeout
    self.progressSleep = progressSleep
    self.timeoutSleep = timeoutSleep
    self.onAuthenticationRequired = onAuthenticationRequired
    liveSubscription = HomeAssistantEVChargingLiveSubscription(
      client: client,
      progressDelay: progressDelay,
      sleep: progressSleep
    )
    canReconcileLateModeChanges = mode != nil
  }
  func load() async {
    guard !isChanging else { return }
    let generation = UUID()
    operationGeneration = generation
    canReconcileLateModeChanges = true
    (isLoading, isLive, isActivityLive, isRefreshing, problem) = (
      true, false, false, false, nil
    )
    scheduleProgress(for: generation)
    do {
      let snapshot = try await client.loadEVChargingSnapshot()
      try Task.checkCancellation()
      guard operationGeneration == generation else { return }
      mode = snapshot.mode
      activity = snapshot.activity
      problem = nil
      finishLoad(isLive: true, activityIsLive: snapshot.activity != .unavailable)
    } catch is CancellationError {
      guard operationGeneration == generation else { return }
      finishLoad(isLive: false)
    } catch {
      guard operationGeneration == generation else { return }
      guard !Task.isCancelled, !Self.isCancellation(error) else {
        finishLoad(isLive: false)
        return
      }
      let loadProblem = Self.problem(for: error, operation: .loading)
      problem = loadProblem
      finishLoad(isLive: false)
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
    liveSubscription.beginModeChange()
    canReconcileLateModeChanges = true
    (mode, isActivityLive, isChanging, problem) = (
      requestedMode, false, true, nil
    )
    scheduleProgress(for: generation)
    await tasks.changeMode(
      client: client,
      requestedMode: requestedMode,
      timeout: updateTimeout,
      sleep: timeoutSleep,
      handlers: .init(
        isActive: { [weak self] in
          self?.operationGeneration == generation && self?.isChanging == true
        },
        receive: { [weak self] result in
          self?.receiveModeChangeResult(
            result, requestedMode: requestedMode, generation: generation
          )
        },
        onTimeout: { [weak self] in
          self?.timeOutModeChange(generation: generation, previousMode: previousMode)
        },
        onCancel: { [weak self] in
          self?.cancelModeChange(generation: generation)
        }
      )
    )
  }
  func synchronize(with connection: HomeAssistantConnectionState) async {
    switch connection {
    case .connected: await observeUpdates()
    case .disconnected:
      invalidateConnection()
      (mode, activity) = (nil, .unavailable)
      (isActivityLive, isLoading, isLive, isRefreshing) = (false, false, false, false)
      finishProgress()
      problem = nil
    case .connecting:
      invalidateConnection()
      (isLoading, isLive, isActivityLive, isRefreshing) = (true, false, false, false)
      finishProgress()
      problem = nil
    case .unavailable:
      invalidateConnection()
      finishLoad(isLive: false)
      if problem != .signInRequired { problem = .connectionNeedsManagement }
    }
  }
  private func invalidateConnection() {
    invalidateSubscription()
    invalidateModeChange()
    operationGeneration = UUID()
  }
}

extension HomeAssistantEVChargingStore {
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
    tasks.scheduleProgress(delay: progressDelay, sleep: progressSleep) { [weak self] in
      guard let self, self.operationGeneration == generation else { return }
      self.showsProgress = true
    }
  }
  private func completeModeChange(
    _ confirmedMode: HomeAssistantEVChargingMode,
    requestedMode: HomeAssistantEVChargingMode
  ) {
    let confirmation = liveSubscription.confirmModeChange(
      confirmedMode,
      previousMode: rollbackMode,
      activity: activity,
      wasLive: isLive
    )
    (mode, isActivityLive) = (confirmation.mode, confirmation.isActivityLive)
    (isChanging, isLive) = (false, confirmation.isLive)
    finishModeChange()
    if confirmation.mode != requestedMode {
      problem = .updateFailed
    }
  }
  private func cancelModeChange(generation: UUID) {
    guard operationGeneration == generation, isChanging else { return }
    lateModeChangesToReconcile.insert(generation)
    operationGeneration = UUID()
    tasks.cancelModeChange()
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
    (isActivityLive, isChanging, isLive, isRefreshing) = (false, false, false, false)
    finishModeChange()
  }
  private func finishModeChange() {
    finishProgress()
    tasks.finishTimeout()
    rollbackMode = nil
    tasks.finishModeChange()
  }
  private func invalidateModeChange() {
    if isChanging {
      mode = rollbackMode
    }
    tasks.cancelModeChange()
    isChanging = false
    finishModeChange()
    lateModeChangesToReconcile = []
    liveSubscription.invalidate()
    canReconcileLateModeChanges = false
    needsLateModeChangeReconciliation = false
    tasks.finishReconciliation()
  }
  private func timeOutModeChange(
    generation: UUID,
    previousMode: HomeAssistantEVChargingMode?
  ) {
    guard operationGeneration == generation, isChanging else { return }
    lateModeChangesToReconcile.insert(generation)
    operationGeneration = UUID()
    tasks.cancelModeChange()
    mode = previousMode
    (isChanging, isLive, isActivityLive, isRefreshing) = (false, false, false, false)
    problem = .updateTimedOut
    finishProgress()
    tasks.finishTimeout()
    rollbackMode = nil
    tasks.finishModeChange()
    performDeferredLateModeChangeReconciliation()
  }
  private func reconcileLateModeChange() {
    guard canReconcileLateModeChanges else { return }
    guard !isChanging else {
      needsLateModeChangeReconciliation = true
      return
    }
    tasks.finishReconciliation()
    let generation = UUID()
    operationGeneration = generation
    lateReconciliationSubscriptionRevision = liveSubscription.revision
    (isLoading, isLive, isActivityLive, isRefreshing) = (
      true, false, false, false
    )
    scheduleProgress(for: generation)
    tasks.loadReconciliation(client: client) { [weak self] result in
      self?.receiveLateReconciliationResult(result, generation: generation)
    }
  }
  private func receiveLateReconciliationResult(
    _ result: Result<HomeAssistantEVChargingSnapshot, any Error>,
    generation: UUID
  ) {
    guard operationGeneration == generation else { return }
    tasks.finishReconciliation()
    guard liveSubscription.revision == lateReconciliationSubscriptionRevision else {
      finishIgnoredReconciliation()
      return
    }
    switch result {
    case .success(let snapshot):
      guard
        snapshot.isAtLeastAsNew(
          as: liveSubscription.latestLiveModeTimestamp
        )
      else {
        finishIgnoredReconciliation()
        return
      }
      liveSubscription.recordReconciledMode(timestamp: snapshot.modeLastUpdated)
      mode = snapshot.mode
      activity = snapshot.activity
      let live = liveSubscription.loadedSnapshotIsLive
      finishLoad(isLive: live, activityIsLive: live && snapshot.activity != .unavailable)
    case .failure(let error):
      finishLoad(isLive: false)
      let loadProblem = Self.problem(for: error, operation: .loading)
      if problem == nil || loadProblem == .signInRequired {
        problem = loadProblem
      }
      if loadProblem == .signInRequired {
        onAuthenticationRequired()
      }
    }
  }
  private func finishIgnoredReconciliation() {
    let live = liveSubscription.isLive
    finishLoad(
      isLive: live && mode != nil,
      activityIsLive: live && activity != .unavailable
    )
  }
  private func performDeferredLateModeChangeReconciliation() {
    guard needsLateModeChangeReconciliation else { return }
    needsLateModeChangeReconciliation = false
    reconcileLateModeChange()
  }
}

extension HomeAssistantEVChargingStore {
  private func observeUpdates() async {
    let generation = beginUpdateObservation()
    for await event in liveSubscription.events() {
      guard !Task.isCancelled, liveSubscription.isCurrent(generation) else { return }
      receiveUpdateEvent(event)
    }
  }
  private func beginUpdateObservation() -> UUID {
    let preservesRefreshPresentation = isRefreshing && problem == nil
    let generation = liveSubscription.begin(
      preservingModeChangeSequence: isChanging
    )
    if preservesRefreshPresentation {
      isLoading = false
    } else {
      (isLoading, isLive, isActivityLive, problem) = (true, false, false, nil)
      isRefreshing = false
    }
    finishProgress()
    return generation
  }
  private func receiveUpdateEvent(_ event: HomeAssistantEVChargingLiveSubscription.Event) {
    switch event {
    case .progress:
      if liveSubscription.shouldShowProgress { showsProgress = true }
    case .update(let update):
      apply(
        liveSubscription.presentation(
          for: update,
          current: .init(store: self),
          isChanging: isChanging
        ))
    case .finished:
      if liveSubscription.expectsContinuousUpdates {
        finishSubscription(problem: .connectionUnavailable)
      } else {
        finishOneShotSubscription()
      }
    case .failed(let error):
      finishSubscription(problem: Self.problem(for: error, operation: .loading))
    }
  }
  private func invalidateSubscription() { liveSubscription.invalidate() }
  private func finishLoad(isLive: Bool, activityIsLive: Bool = false) {
    (isLoading, self.isLive, isActivityLive, isRefreshing) = (
      false, isLive, activityIsLive, false
    )
    finishProgress()
  }
  private func finishProgress() {
    tasks.finishProgress()
    showsProgress = false
  }
  private func apply(
    _ presentation: HomeAssistantEVChargingLiveSubscription.Presentation
  ) {
    (mode, activity) = (presentation.mode, presentation.activity)
    (isLoading, isLive, isActivityLive) = (
      false, presentation.isLive, presentation.isActivityLive
    )
    isRefreshing = presentation.isRefreshing
    problem = presentation.problem
    if presentation.finishesProgress { finishProgress() }
  }
  private func finishSubscription(problem: Problem) {
    liveSubscription.finish()
    (isLoading, isLive, isActivityLive, isRefreshing) = (false, false, false, false)
    self.problem = problem
    if problem == .signInRequired { onAuthenticationRequired() }
    if !isChanging { finishProgress() }
  }
  private func finishOneShotSubscription() {
    liveSubscription.finish()
    (isLoading, isRefreshing) = (false, false)
    finishProgress()
  }
}

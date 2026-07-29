import Foundation

@MainActor
final class HomeAssistantEVChargingStore: ObservableObject {
  @Published var mode: HomeAssistantEVChargingMode?
  @Published var activity: HomeAssistantEVChargingActivity
  @Published var isActivityLive: Bool
  @Published var isLoading = false
  @Published var isLive = false
  @Published var isRefreshing = false
  @Published var isChanging = false
  @Published var showsProgress = false
  @Published var problem: Problem?
  private let client: any HomeAssistantEVCharging
  let onAuthenticationRequired: @MainActor @Sendable () -> Void
  private let progressDelay, updateTimeout: Duration
  private let progressSleep, timeoutSleep: @Sendable (Duration) async -> Void
  let liveSubscription: HomeAssistantEVChargingLiveSubscription
  let tasks = HomeAssistantEVChargingTasks()
  var operationGeneration = UUID()
  private var rollbackMode: HomeAssistantEVChargingMode?
  private var lateReconciliationSubscriptionRevision = 0
  var lateModeChangesToReconcile: Set<UUID> = []
  var canReconcileLateModeChanges = false, needsLateModeChangeReconciliation = false
  init(
    client: any HomeAssistantEVCharging,
    mode: HomeAssistantEVChargingMode? = nil,
    activity: HomeAssistantEVChargingActivity = .unavailable,
    hasCompletedDiscovery: Bool? = nil,
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
      hasCompletedDiscovery: hasCompletedDiscovery ?? (mode != nil),
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
    liveSubscription.invalidate()
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
  func finishModeChange() {
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

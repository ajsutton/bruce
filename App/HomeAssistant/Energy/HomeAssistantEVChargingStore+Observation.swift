import Foundation

extension HomeAssistantEVChargingStore {
  func observeUpdates() async {
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
      (isLoading, isLive, isActivityLive, isDecisionLive, problem) = (
        true, false, false, false, nil
      )
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
      if update == .absent {
        invalidateModeChangeForAbsence()
      }
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

  private func invalidateModeChangeForAbsence() {
    guard isChanging else { return }
    operationGeneration = UUID()
    tasks.cancelModeChange()
    isChanging = false
    finishModeChange()
    lateModeChangesToReconcile = []
    canReconcileLateModeChanges = false
    needsLateModeChangeReconciliation = false
    tasks.finishReconciliation()
  }

  var hasCompletedDiscovery: Bool { liveSubscription.hasCompletedDiscovery }

  func finishLoad(
    isLive: Bool,
    activityIsLive: Bool = false,
    decisionIsLive: Bool = false
  ) {
    (isLoading, self.isLive, isActivityLive, isDecisionLive, isRefreshing) = (
      false, isLive, activityIsLive, decisionIsLive, false
    )
    finishProgress()
  }

  func finishProgress() {
    tasks.finishProgress()
    showsProgress = false
  }

  private func apply(
    _ presentation: HomeAssistantEVChargingLiveSubscription.Presentation
  ) {
    (mode, activity, decision) = (
      presentation.mode, presentation.activity, presentation.decision
    )
    (isLoading, isLive, isActivityLive, isDecisionLive) = (
      false,
      presentation.isLive,
      presentation.isActivityLive,
      presentation.isDecisionLive
    )
    isRefreshing = presentation.isRefreshing
    problem = presentation.problem
    if presentation.finishesProgress { finishProgress() }
  }

  private func finishSubscription(problem: Problem) {
    liveSubscription.finish()
    (isLoading, isLive, isActivityLive, isDecisionLive, isRefreshing) = (
      false, false, false, false, false
    )
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

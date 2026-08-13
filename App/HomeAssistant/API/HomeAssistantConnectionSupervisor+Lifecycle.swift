import Foundation

extension HomeAssistantConnectionSupervisor {
  func isCurrent(
    lifecycleID: UUID,
    attemptID: UUID,
    authenticationSessionEpoch: Int
  ) -> Bool {
    isCurrentLifecycle(lifecycleID)
      && currentAttempt?.id == attemptID
      && credentialSnapshot?.authenticationSessionEpoch == authenticationSessionEpoch
  }

  func isCurrentLifecycle(_ id: UUID) -> Bool {
    publicationLifecycleID == id
  }

  func startLifecycleIfNeeded(trigger: HomeAssistantConnectionTrigger) {
    guard isRunnable, lifecycleTask == nil else { return }
    shouldRestartAfterLifecycleEnds = false
    let id = UUID()
    runningLifecycleID = id
    publicationLifecycleID = id
    lifecycleTask = Task {
      await runLifecycle(id: id, trigger: trigger)
      lifecycleDidFinish(id: id)
    }
  }

  func stopCurrentLifecycle(restartWhenRunnable: Bool) {
    shouldRestartAfterLifecycleEnds = restartWhenRunnable
    invalidateStabilityTimer()
    publicationLifecycleID = nil
    let stoppedAttempt = currentAttempt
    currentAttempt = nil
    currentConnection?.cancel()
    if let stoppedAttempt {
      Task { await stoppedAttempt.finish() }
    }
    lifecycleTask?.cancel()
  }

  func lifecycleDidFinish(id: UUID) {
    guard runningLifecycleID == id else { return }
    lifecycleTask = nil
    runningLifecycleID = nil
    publicationLifecycleID = nil
    currentConnection = nil
    currentAttempt = nil
    currentAccess = nil
    stableConnectionTask?.cancel()
    stableConnectionTask = nil
    let shouldRestart = shouldRestartAfterLifecycleEnds
    let restartTrigger = pendingReplacementTrigger ?? .consumerIntent
    pendingReplacementTrigger = nil
    shouldRestartAfterLifecycleEnds = false
    if shouldRestart || isRunnable {
      reconcileLifecycle(trigger: restartTrigger)
    }
  }
}

import Foundation

extension HomeAssistantConnectionSupervisor {
  typealias Update = HomeAssistantStateUpdate
  typealias Stream = HomeAssistantBufferedUpdateStream<Update>
  typealias Continuation = Stream.Continuation

  var hasConsumerIntent: Bool {
    !continuations.isEmpty || !readinessWaiters.isEmpty || activeCommandCount > 0
  }

  var isRunnable: Bool {
    !isExplicitlyStopped
      && hasConsumerIntent
      && isApplicationActive
      && credentialSnapshot?.availability == .ready
      && !requiresUserAction
  }

  func prepareForDisconnect() async -> UUID {
    let preparationID = UUID()
    disconnectPreparationID = preparationID
    isExplicitlyStopped = true
    shutdownGeneration = UUID()
    let lifecycleTask = lifecycleTask
    let credentialTask = credentialTask
    publishReconnecting()
    failReadinessWaiters(with: CancellationError())
    stopCurrentLifecycle(restartWhenRunnable: false)
    credentialTask?.cancel()
    self.credentialTask = nil
    transition(to: .stopped, trigger: .consumerIntent)
    await lifecycleTask?.value
    await credentialTask?.value
    return preparationID
  }

  func recoverFromFailedDisconnect(preparationID: UUID) {
    guard disconnectPreparationID == preparationID else { return }
    disconnectPreparationID = nil
    isExplicitlyStopped = false
    startCredentialObservationIfNeeded()
    reconcileLifecycle(trigger: .credentials)
  }
}

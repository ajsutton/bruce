import Foundation

extension HomeAssistantConnectionSupervisor {
  func addConsumer(id: UUID, continuation: Continuation) {
    continuations[id] = continuation
    if let latestUpdate {
      continuation.yield(latestUpdate)
    }
    guard disconnectPreparationID == nil else { return }
    isExplicitlyStopped = false
    startCredentialObservationIfNeeded()
    reconcileLifecycle(trigger: .consumerIntent)
  }

  func removeConsumer(id: UUID) {
    continuations[id] = nil
    reconcileLifecycle(trigger: .consumerIntent)
  }

  func cancelReadinessWaiter(id: UUID) {
    guard let continuation = readinessWaiters.removeValue(forKey: id) else { return }
    continuation.resume(throwing: CancellationError())
    reconcileLifecycle(trigger: .consumerIntent)
  }

  func startCredentialObservationIfNeeded() {
    guard credentialTask == nil else { return }
    let generation = shutdownGeneration
    credentialTask = Task { [credentialEvents] in
      let initial = await session.connectionSnapshot()
      guard !Task.isCancelled, shutdownGeneration == generation, !isExplicitlyStopped else {
        return
      }
      receiveCredentialSnapshot(initial)
      for await snapshot in await credentialEvents.updates() {
        guard !Task.isCancelled, shutdownGeneration == generation, !isExplicitlyStopped else {
          return
        }
        receiveCredentialSnapshot(snapshot)
      }
    }
  }
}

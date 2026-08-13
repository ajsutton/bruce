import Foundation

extension HomeAssistantConnectionSupervisor: HomeAssistantWebSocketCommanding {
  func perform(_ command: HomeAssistantWebSocketCommand) async throws -> Data {
    guard disconnectPreparationID == nil else { throw HomeAssistantAPIError.noCredentials }
    activeCommandCount += 1
    defer {
      activeCommandCount -= 1
      reconcileLifecycle(trigger: .consumerIntent)
    }
    if state != .live {
      try await requireFreshLiveData()
    }
    guard
      state == .live,
      let connection = currentConnection,
      let attempt = currentAttempt
    else { throw HomeAssistantAPIError.staleOperation }
    let lifecycleID = runningLifecycleID
    let attemptID = attempt.id
    let id = try await attempt.allocateCommandID()
    do {
      try await connection.send(command.data(id: id))
    } catch {
      if runningLifecycleID == lifecycleID, currentAttempt?.id == attemptID {
        await attempt.finish(throwing: error)
        connection.cancel()
      }
      throw error
    }
    let response = try await withPhaseDeadline {
      try await attempt.response(for: id)
    } onTimeout: {
      await attempt.finish(throwing: URLError(.timedOut))
      connection.cancel()
    }
    guard runningLifecycleID == lifecycleID, currentAttempt?.id == attemptID else {
      throw HomeAssistantAPIError.staleOperation
    }
    return response
  }
}

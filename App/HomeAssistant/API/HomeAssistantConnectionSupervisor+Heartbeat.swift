import Foundation

extension HomeAssistantConnectionSupervisor {
  func makeHeartbeat(
    connection: any HomeAssistantWebSocketConnection,
    attempt: HomeAssistantConnectionAttempt,
    lifecycleID: UUID,
    attemptID: UUID
  ) -> Task<Void, Never> {
    Task {
      do {
        try await monitorHeartbeat(
          connection: connection,
          attempt: attempt,
          lifecycleID: lifecycleID,
          attemptID: attemptID
        )
      } catch is CancellationError {
        return
      } catch {
        await attempt.finish(throwing: error)
        connection.cancel()
      }
    }
  }

  private func monitorHeartbeat(
    connection: any HomeAssistantWebSocketConnection,
    attempt: HomeAssistantConnectionAttempt,
    lifecycleID: UUID,
    attemptID: UUID
  ) async throws {
    let tolerance = heartbeatIdleInterval.scaled(by: 0.1)
    while !Task.isCancelled {
      let scheduledAt = clock.now()
      try await clock.sleep(heartbeatIdleInterval, tolerance)
      try Task.checkCancellation()
      guard runningLifecycleID == lifecycleID, currentAttempt?.id == attemptID else {
        throw CancellationError()
      }
      let firedAt = clock.now()
      if firedAt - scheduledAt > heartbeatIdleInterval.secondsValue
        + heartbeatResponseDeadline.secondsValue
      {
        throw URLError(.timedOut)
      }
      let lastInbound = await attempt.lastInboundMessageAt
      guard firedAt - lastInbound >= heartbeatIdleInterval.secondsValue else {
        continue
      }
      try await sendHeartbeat(connection: connection, attempt: attempt)
    }
  }

  private func sendHeartbeat(
    connection: any HomeAssistantWebSocketConnection,
    attempt: HomeAssistantConnectionAttempt
  ) async throws {
    let id = try await attempt.allocateCommandID()
    try await connection.send(
      JSONEncoder().encode(HomeAssistantPingCommand(id: id, type: "ping"))
    )
    let response = try await withThrowingTaskGroup(of: Data.self) { group in
      group.addTask { try await attempt.response(for: id) }
      group.addTask { [clock, heartbeatResponseDeadline, attempt] in
        try await clock.sleep(
          heartbeatResponseDeadline,
          heartbeatResponseDeadline.scaled(by: 0.1)
        )
        let timeout = URLError(.timedOut)
        await attempt.finish(throwing: timeout)
        throw timeout
      }
      guard let result = try await group.next() else {
        throw URLError(.timedOut)
      }
      group.cancelAll()
      return result
    }
    let pong = try JSONDecoder().decode(HomeAssistantPongMessage.self, from: response)
    guard pong.id == id, pong.type == "pong" else {
      throw HomeAssistantAPIError.invalidResponse
    }
  }
}

private struct HomeAssistantPingCommand: Encodable {
  let id: Int
  let type: String
}

private struct HomeAssistantPongMessage: Decodable {
  let id: Int
  let type: String
}

extension Duration {
  fileprivate var secondsValue: TimeInterval {
    let components = self.components
    return Double(components.seconds)
      + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }

  fileprivate func scaled(by scale: Double) -> Duration {
    .nanoseconds(Int64(secondsValue * scale * 1_000_000_000))
  }
}

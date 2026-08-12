import Foundation

struct HomeAssistantReconnectAttempt {
  var publishedSnapshot: Bool
  private let previouslyPublishedSnapshot: Bool
  var attemptedAccess: HomeAssistantWebSocketAccess?
  var latestStates: [HomeAssistantState]
  let generation: UUID

  var hasPublishedSnapshot: Bool {
    previouslyPublishedSnapshot || publishedSnapshot
  }

  static func starting(
    hasPublishedSnapshot: Bool,
    latestStates: [HomeAssistantState]
  ) -> Self {
    Self(
      publishedSnapshot: false,
      previouslyPublishedSnapshot: hasPublishedSnapshot,
      attemptedAccess: nil,
      latestStates: latestStates,
      generation: UUID()
    )
  }
}

struct HomeAssistantReconnectState {
  var retryIndex = 0
  var lastFailedURL: URL?
  var refreshedAfterUnauthorized = false
}

extension HomeAssistantStateStream {
  func monitorLiveness(
    of connection: any HomeAssistantWebSocketConnection,
    monitor: HomeAssistantHeartbeatMonitor
  ) async {
    while !Task.isCancelled {
      do {
        try await heartbeatSleep(heartbeatInterval)
        try Task.checkCancellation()
        try await connection.ping()
      } catch is CancellationError {
        return
      } catch {
        await monitor.record(error)
        connection.cancel()
        return
      }
    }
  }

  func waitForRetry(_ delay: Duration) async -> Bool {
    do {
      try await sleep(delay)
      return true
    } catch {
      return false
    }
  }

  func recoverSubscription(
    from error: any Error,
    attempt: HomeAssistantReconnectAttempt,
    state: inout HomeAssistantReconnectState,
    continuation: HomeAssistantBufferedUpdateStream<
      HomeAssistantStateUpdate
    >.Continuation
  ) async -> Bool {
    if case HomeAssistantAPIError.staleOperation = error,
      let attemptedAccess = attempt.attemptedAccess
    {
      do {
        try await session.validateWebSocketAccess(attemptedAccess)
      } catch {
        Self.reportTerminalDisconnect(error)
        continuation.finish(throwing: error)
        return false
      }
    }
    guard case HomeAssistantAPIError.unauthorized = error,
      let attemptedAccess = attempt.attemptedAccess,
      !state.refreshedAfterUnauthorized
    else {
      return await recover(
        from: error,
        attempt: attempt,
        retryIndex: &state.retryIndex,
        lastFailedURL: &state.lastFailedURL,
        continuation: continuation
      )
    }
    do {
      try await session.refreshRejectedWebSocketAccess(attemptedAccess)
      state.refreshedAfterUnauthorized = true
      Self.reportDisconnect(
        error,
        update: .reconnecting(attempt.latestStates, generation: attempt.generation),
        to: continuation
      )
      return true
    } catch is CancellationError {
      continuation.finish()
      return false
    } catch {
      return await recover(
        from: error,
        attempt: attempt,
        retryIndex: &state.retryIndex,
        lastFailedURL: &state.lastFailedURL,
        continuation: continuation
      )
    }
  }

  func recover(
    from error: any Error,
    attempt: HomeAssistantReconnectAttempt,
    retryIndex: inout Int,
    lastFailedURL: inout URL?,
    continuation: HomeAssistantBufferedUpdateStream<
      HomeAssistantStateUpdate
    >.Continuation
  ) async -> Bool {
    guard
      let delay = reconnectDelay(
        after: error,
        attempt: attempt,
        retryIndex: &retryIndex,
        lastFailedURL: &lastFailedURL
      )
    else {
      Self.reportTerminalDisconnect(error)
      continuation.finish(throwing: error)
      return false
    }
    Self.reportDisconnect(
      error,
      update: .reconnecting(
        attempt.latestStates,
        generation: attempt.generation
      ),
      to: continuation
    )
    guard await waitForRetry(delay) else {
      continuation.finish()
      return false
    }
    return true
  }

  private func reconnectDelay(
    after error: any Error,
    attempt: HomeAssistantReconnectAttempt,
    retryIndex: inout Int,
    lastFailedURL: inout URL?
  ) -> Duration? {
    guard Self.shouldReconnect(after: error, attempt: attempt), !retryDelays.isEmpty else {
      return nil
    }
    if !Self.preservesPreferredRoute(after: error) {
      lastFailedURL = attempt.attemptedAccess?.baseURL ?? lastFailedURL
    }
    retryIndex = attempt.publishedSnapshot ? 0 : retryIndex
    let delay = retryDelays[min(retryIndex, retryDelays.count - 1)]
    retryIndex = min(retryIndex + 1, retryDelays.count - 1)
    return delay
  }

  private static func preservesPreferredRoute(after error: any Error) -> Bool {
    if case HomeAssistantAPIError.staleOperation = error {
      return true
    }
    return false
  }
}

actor HomeAssistantHeartbeatMonitor {
  private(set) var failure: (any Error)?

  func record(_ error: any Error) {
    failure = error
  }
}

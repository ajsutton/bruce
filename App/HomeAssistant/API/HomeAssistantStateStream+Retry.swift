import Foundation

struct HomeAssistantReconnectAttempt {
  let publishedSnapshot: Bool
  let attemptedURL: URL?
  let latestStates: [HomeAssistantState]
  let generation: UUID
}

extension HomeAssistantStateStream {
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
    guard Self.shouldReconnect(after: error), !retryDelays.isEmpty else {
      return nil
    }
    lastFailedURL = attempt.attemptedURL ?? lastFailedURL
    retryIndex = attempt.publishedSnapshot ? 0 : retryIndex
    let delay = retryDelays[min(retryIndex, retryDelays.count - 1)]
    retryIndex = min(retryIndex + 1, retryDelays.count - 1)
    return delay
  }
}

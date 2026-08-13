import Foundation

struct HomeAssistantTemperatureUpdateStream: AsyncSequence, Sendable {
  typealias Element = HomeAssistantTemperatureUpdate
  typealias Continuation = HomeAssistantBufferedUpdateStream<Element>.Continuation
  typealias AsyncIterator = HomeAssistantBufferedUpdateStream<Element>.AsyncIterator

  private let updates: HomeAssistantBufferedUpdateStream<Element>
  private let waitForSubscription: @Sendable () async throws -> Void

  init(_ build: (Continuation) -> Void) {
    updates = HomeAssistantBufferedUpdateStream(build)
    waitForSubscription = {}
  }

  init(
    waitUntilSubscribed: @escaping @Sendable () async throws -> Void,
    _ build: (Continuation) -> Void
  ) {
    updates = HomeAssistantBufferedUpdateStream(build)
    waitForSubscription = waitUntilSubscribed
  }

  func makeAsyncIterator() -> AsyncIterator {
    updates.makeAsyncIterator()
  }

  func cancel() {
    updates.cancel()
  }

  func waitUntilSubscribed() async throws {
    try await waitForSubscription()
  }
}

protocol HomeAssistantTemperatureLoading: Sendable {
  var providesContinuousTemperatureUpdates: Bool { get }

  func temperatureUpdates() -> HomeAssistantTemperatureUpdateStream
}

extension HomeAssistantTemperatureLoading {
  var providesContinuousTemperatureUpdates: Bool { false }
}

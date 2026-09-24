import Combine
import XCTest

@testable import Bruce

@MainActor
final class ClimateHistorySamplingTests: XCTestCase {
  func testTrailingTimerPublishesOnlyNewestQueuedSampleWithoutReload() async throws {
    let source = ClimateHistoryTestSource()
    let sleeper = ClimateHistoryTestSleeper()
    let store = ClimateHistoryStore(
      source: source, loader: source, now: { source.now }, sleep: sleeper.sleep)
    let task = Task { await store.observe(hours: 12) }
    defer {
      task.cancel()
      source.finish()
      sleeper.finish()
    }
    let generation = UUID()
    try await loadInitial(store: store, source: source, generation: generation)
    source.advance(1)
    source.yield(.live(try source.states(actual: 25), generation: generation))
    await fulfillment(of: [sleeper.started[0]], timeout: 1)
    source.advance(1)
    let consumed = source.expectDateRead()
    source.yield(.live(try source.states(actual: 26), generation: generation))
    await fulfillment(of: [consumed], timeout: 1)
    XCTAssertEqual(store.history?.frames.last?.values["climate.lounge"]?.actual, 24)
    let published = expectation(description: "Newest trailing value published")
    let subscription = store.$history.dropFirst().prefix(1).sink { _ in published.fulfill() }
    sleeper.resume(0)
    await fulfillment(of: [published], timeout: 1)
    XCTAssertEqual(store.history?.frames.map { $0.values["climate.lounge"]?.actual }, [24, 26])
    XCTAssertEqual(source.requestCount, 1)
    withExtendedLifetime(subscription) {}
  }

  func testCancelledTimerCannotFlushReplacementQueueAfterReconnect() async throws {
    let source = ClimateHistoryTestSource()
    let sleeper = ClimateHistoryTestSleeper()
    let store = ClimateHistoryStore(
      source: source, loader: source, now: { source.now }, sleep: sleeper.sleep)
    let task = Task { await store.observe(hours: 12) }
    defer {
      task.cancel()
      source.finish()
      sleeper.finish()
    }
    let generation = UUID()
    try await loadInitial(store: store, source: source, generation: generation)
    source.advance(1)
    source.yield(.live(try source.states(actual: 25), generation: generation))
    await fulfillment(of: [sleeper.started[0]], timeout: 1)
    source.yield(.reconnecting([], generation: generation))
    source.yield(.live(try source.states(actual: 26), generation: generation))
    await fulfillment(of: [source.started[1]], timeout: 1)
    // The first post-reconnect live frame is queued against the preserved graph.
    await fulfillment(of: [sleeper.started[1]], timeout: 1)
    sleeper.resume(0)
    await fulfillment(of: [sleeper.returned[0]], timeout: 1)
    XCTAssertEqual(store.history?.frames.last?.values["climate.lounge"]?.actual, 24)
    let loaded = expectation(description: "Replacement history installed")
    let subscription = store.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in
      loaded.fulfill()
    }
    source.complete(1, result: .success(source.history()))
    await fulfillment(of: [loaded], timeout: 1)
    XCTAssertEqual(store.history?.frames.last?.values["climate.lounge"]?.actual, 26)
    XCTAssertEqual(source.requestCount, 2)
    withExtendedLifetime(subscription) {}
  }

  private func loadInitial(
    store: ClimateHistoryStore, source: ClimateHistoryTestSource, generation: UUID
  ) async throws {
    await fulfillment(of: [source.subscribed], timeout: 1)
    source.yield(.live(try source.states(), generation: generation))
    await fulfillment(of: [source.started[0]], timeout: 1)
    let loaded = expectation(description: "Initial history installed")
    let subscription = store.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in
      loaded.fulfill()
    }
    source.complete(0, result: .success(source.history()))
    await fulfillment(of: [loaded], timeout: 1)
    withExtendedLifetime(subscription) {}
  }
}

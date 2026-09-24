import Combine
import XCTest

@testable import Bruce

@MainActor
final class ClimateHistoryStoreTests: XCTestCase {
  func testInitialHistoryMergesLiveState() async throws {
    let source = ClimateHistoryTestSource()
    let store = ClimateHistoryStore(source: source, loader: source, now: { source.now })
    let task = Task { await store.observe(hours: 12) }
    defer {
      task.cancel()
      source.finish()
    }
    await fulfillment(of: [source.subscribed], timeout: 1)
    source.yield(.live(try source.states()))
    await fulfillment(of: [source.started[0]], timeout: 1)
    let loaded = expectation(description: "History installed")
    let subscription = store.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in
      loaded.fulfill()
    }
    source.complete(0, result: .success(source.history()))
    await fulfillment(of: [loaded], timeout: 1)
    XCTAssertEqual(store.history?.frames.last?.values["climate.lounge"]?.actual, 24)
    XCTAssertEqual(store.history?.frames.last?.values["climate.lounge"]?.opening, 80)
    XCTAssertFalse(store.isStale)
    XCTAssertEqual(source.requestCount, 1)
    withExtendedLifetime(subscription) {}
  }

  func testBurstWhileLoadingDoesNotRefetchHistoryAndKeepsNewestSample() async throws {
    let source = ClimateHistoryTestSource()
    let store = ClimateHistoryStore(source: source, loader: source, now: { source.now })
    let task = Task { await store.observe(hours: 12) }
    defer {
      task.cancel()
      source.finish()
    }
    await fulfillment(of: [source.subscribed], timeout: 1)
    let generation = UUID()
    source.yield(.live(try source.states(), generation: generation))
    await fulfillment(of: [source.started[0]], timeout: 1)
    let remote = source.history()
    source.advance(10)
    for index in 0..<100 {
      source.yield(.live(try source.states(actual: Double(index)), generation: generation))
    }
    // A semantic transition is delivered immediately, providing an observable consumer barrier.
    source.yield(.reconnecting([], generation: generation))
    source.yield(.live(try source.states(actual: 99), generation: generation))
    await fulfillment(of: [source.started[1]], timeout: 1)
    XCTAssertEqual(source.requestCount, 2)
    let loaded = expectation(description: "Reconnected history installed")
    let subscription = store.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in
      loaded.fulfill()
    }
    source.complete(1, result: .success(source.history()))
    source.complete(0, result: .success(remote))
    await fulfillment(of: [loaded, source.returned[0]], timeout: 1)
    XCTAssertEqual(store.history?.frames.last?.values["climate.lounge"]?.actual, 99)
    XCTAssertFalse(store.isStale)
    withExtendedLifetime(subscription) {}
  }

  func testResetRejectsLateHistoryAndReleasesSubscription() async throws {
    let source = ClimateHistoryTestSource()
    let store = ClimateHistoryStore(source: source, loader: source, now: { source.now })
    let task = Task { await store.observe(hours: 12) }
    defer {
      task.cancel()
      source.finish()
    }
    await fulfillment(of: [source.subscribed], timeout: 1)
    source.yield(.live(try source.states()))
    await fulfillment(of: [source.started[0]], timeout: 1)
    store.reset()
    source.complete(0, result: .success(source.history()))
    await fulfillment(of: [source.returned[0], source.terminated], timeout: 1)
    await task.value
    XCTAssertNil(store.history)
    XCTAssertFalse(store.isLoading)
  }

  func testFailureIsVisibleAndDoesNotLeaveSpinnerRunning() async throws {
    let source = ClimateHistoryTestSource()
    let store = ClimateHistoryStore(source: source, loader: source, now: { source.now })
    let task = Task { await store.observe(hours: 12) }
    defer {
      task.cancel()
      source.finish()
    }
    await fulfillment(of: [source.subscribed], timeout: 1)
    source.yield(.live(try source.states()))
    await fulfillment(of: [source.started[0]], timeout: 1)
    let failed = expectation(description: "History failure shown")
    let subscription = store.$hasLoadError.filter { $0 }.prefix(1).sink { _ in failed.fulfill() }
    source.complete(0, result: .failure(HomeAssistantAPIError.invalidResponse))
    await fulfillment(of: [failed], timeout: 1)
    XCTAssertFalse(store.isLoading)
    XCTAssertTrue(store.isStale)
    withExtendedLifetime(subscription) {}
  }
}

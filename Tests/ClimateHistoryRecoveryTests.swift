import Combine
import XCTest

@testable import Bruce

@MainActor
final class ClimateHistoryRecoveryTests: XCTestCase {
  func testReconnectRequestsOnlyGapAndPreservesEarlierHistory() async throws {
    let source = ClimateHistoryTestSource()
    let store = ClimateHistoryStore(source: source, loader: source, now: { source.now })
    let task = Task { await store.observe(hours: 12) }
    defer {
      task.cancel()
      source.finish()
    }
    let generation = UUID()
    try await loadInitial(store: store, source: source, generation: generation)
    let previousEnd = try XCTUnwrap(store.history?.interval.end)
    let stale = expectation(description: "Disconnect consumed")
    let status = store.$isStale.dropFirst().filter { $0 }.prefix(1).sink { _ in stale.fulfill() }
    source.yield(.reconnecting(try source.states(), generation: generation))
    await fulfillment(of: [stale], timeout: 1)
    source.advance(300)
    source.yield(.live(try source.states(actual: 23), generation: UUID()))
    await fulfillment(of: [source.started[1]], timeout: 1)
    XCTAssertEqual(source.requestedIntervals[1], DateInterval(start: previousEnd, end: source.now))
    let loaded = completion(store)
    source.complete(
      1,
      result: .success(
        ClimateHistory(
          interval: source.requestedIntervals[1],
          frames: [
            .init(
              timestamp: previousEnd,
              values: [
                "climate.lounge": .init(actual: 24, target: 21, opening: 80, activity: .active)
              ])
          ])))
    await fulfillment(of: [loaded.0], timeout: 1)
    XCTAssertEqual(store.history?.frames.first?.timestamp, previousEnd.addingTimeInterval(-3600))
    XCTAssertEqual(store.history?.frames.last?.values["climate.lounge"]?.actual, 23)
    XCTAssertEqual(source.requestCount, 2)
    withExtendedLifetime([status, loaded.1]) {}
  }

  func testCoalescedSourceReplacementClearsOldHistoryBeforeNewLoad() async throws {
    let source = ClimateHistoryTestSource()
    let store = ClimateHistoryStore(source: source, loader: source, now: { source.now })
    let task = Task { await store.observe(hours: 12) }
    defer {
      task.cancel()
      source.finish()
    }
    try await loadInitial(store: store, source: source, generation: UUID())
    let cleared = expectation(description: "Old source cleared")
    let subscription = store.$history.dropFirst().filter { $0 == nil }.prefix(1).sink { _ in
      cleared.fulfill()
    }
    let replacement = UUID()
    let states = try source.states(actual: 18)
    source.yield(.reconnecting(states, generation: replacement))
    source.yield(.live(states, generation: replacement))
    await fulfillment(of: [cleared, source.started[1]], timeout: 1)
    XCTAssertNil(store.history)
    let failed = expectation(description: "Replacement load failed")
    let failure = store.$hasLoadError.filter { $0 }.prefix(1).sink { _ in failed.fulfill() }
    source.complete(1, result: .failure(HomeAssistantAPIError.invalidResponse))
    await fulfillment(of: [failed], timeout: 1)
    XCTAssertNil(store.history)
    withExtendedLifetime([subscription, failure]) {}
  }

  func testShorterWindowRetainsBoundaryValueAndUsesSelectedDuration() {
    let end = Date(timeIntervalSince1970: 100_000)
    let history = ClimateHistory(
      interval: DateInterval(start: end.addingTimeInterval(-12 * 3600), end: end),
      frames: [
        .init(
          timestamp: end.addingTimeInterval(-2 * 3600),
          values: ["climate.lounge": .init(actual: 24, target: 21, opening: 0, activity: .off)]),
        .init(
          timestamp: end,
          values: ["climate.lounge": .init(actual: 23, target: 21, opening: 0, activity: .off)]),
      ])
    let selected = history.window(duration: 3600)
    XCTAssertEqual(selected.interval.duration, 3600)
    XCTAssertEqual(
      selected.points(for: ClimateHistoryZone.all[0]).first?.timestamp,
      end.addingTimeInterval(-3600))
    XCTAssertEqual(selected.points(for: ClimateHistoryZone.all[0]).first?.value.actual, 24)
  }

  func testRegistryGenerationChangeDoesNotClearOrReloadHistory() async throws {
    let source = ClimateHistoryTestSource()
    let store = ClimateHistoryStore(source: source, loader: source, now: { source.now })
    let task = Task { await store.observe(hours: 12) }
    defer {
      task.cancel()
      source.finish()
    }
    try await loadInitial(store: store, source: source, generation: UUID())
    let consumed = source.expectDateRead()
    source.yield(.live(try source.states(), generation: UUID()))
    await fulfillment(of: [consumed], timeout: 1)
    XCTAssertNotNil(store.history)
    XCTAssertFalse(store.isLoading)
    XCTAssertEqual(source.requestCount, 1)
  }

  func testRetryAfterFailedGapRequestsOnlyTheUnfilledGap() async throws {
    let source = ClimateHistoryTestSource()
    let store = ClimateHistoryStore(source: source, loader: source, now: { source.now })
    let task = Task { await store.observe(hours: 12) }
    defer {
      task.cancel()
      source.finish()
    }
    let generation = UUID()
    try await loadInitial(store: store, source: source, generation: generation)
    let end = source.now
    source.advance(300)
    source.yield(.reconnecting(try source.states(), generation: generation))
    source.yield(.live(try source.states(), generation: generation))
    await fulfillment(of: [source.started[1]], timeout: 1)
    let failed = expectation(description: "Gap failed")
    let failure = store.$hasLoadError.filter { $0 }.prefix(1).sink { _ in failed.fulfill() }
    source.complete(1, result: .failure(HomeAssistantAPIError.invalidResponse))
    await fulfillment(of: [failed], timeout: 1)
    source.advance(300)
    let retry = Task { await store.observe(hours: 12) }
    defer { retry.cancel() }
    await fulfillment(of: [source.subscriptions[1]], timeout: 1)
    source.yield(.live(try source.states(), generation: generation))
    await fulfillment(of: [source.started[2]], timeout: 1)
    XCTAssertEqual(source.requestedIntervals[2], DateInterval(start: end, end: source.now))
    XCTAssertNotNil(store.history)
    withExtendedLifetime(failure) {}
  }

  func testOldHistoryOutsideWindowCannotDuplicateTheNewBoundary() {
    let end = Date(timeIntervalSince1970: 100_000)
    let old = ClimateHistory(
      interval: DateInterval(start: end.addingTimeInterval(-7200), duration: 3600),
      frames: [
        .init(timestamp: end.addingTimeInterval(-7200), values: [:])
      ])
    let current = ClimateHistory(
      interval: DateInterval(start: end.addingTimeInterval(-3600), end: end),
      frames: [
        .init(
          timestamp: end.addingTimeInterval(-3600),
          values: ["climate.lounge": .init(actual: 24, target: 21, opening: 0, activity: .off)])
      ])
    let merged = current.mergingEarlierHistory(old, duration: 3600)
    XCTAssertEqual(merged.frames, current.frames)
    XCTAssertEqual(Set(merged.points(for: ClimateHistoryZone.all[0]).map(\.id)).count, 2)
  }

  private func loadInitial(
    store: ClimateHistoryStore, source: ClimateHistoryTestSource, generation: UUID
  ) async throws {
    await fulfillment(of: [source.subscribed], timeout: 1)
    source.yield(.live(try source.states(), generation: generation))
    await fulfillment(of: [source.started[0]], timeout: 1)
    let loaded = completion(store)
    var history = source.history()
    history.frames = [
      .init(
        timestamp: source.now.addingTimeInterval(-3600),
        values: ["climate.lounge": .init(actual: 25, target: 21, opening: 80, activity: .active)])
    ]
    source.complete(0, result: .success(history))
    await fulfillment(of: [loaded.0], timeout: 1)
    withExtendedLifetime(loaded.1) {}
  }

  private func completion(_ store: ClimateHistoryStore) -> (XCTestExpectation, AnyCancellable) {
    let loaded = expectation(description: "History installed")
    return (
      loaded, store.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in loaded.fulfill() }
    )
  }
}

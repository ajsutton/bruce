import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeEnergyFlowHistoryStoreTests: XCTestCase {
  func testResetRejectsLateFlowHistoryCompletion() async {
    let loader = ControlledFlowHistoryLoader(requestCount: 1)
    let store = HomeEnergyFlowHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)

    let cancelledLoad = store.reset()
    loader.succeed(0, with: completeHistory())
    await fulfillment(of: [loader.finished(at: 0)], timeout: 1)
    await cancelledLoad?.value

    XCTAssertEqual(store.flowHistory, .empty)
    XCTAssertFalse(store.hasUsableHistory)
    XCTAssertFalse(store.isLoading)
    XCTAssertTrue(store.isUnavailable)
  }

  func testReplacementRejectsLateResultFromOlderFlowLoad() async {
    let loader = ControlledFlowHistoryLoader(requestCount: 2)
    let store = HomeEnergyFlowHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    store.reload()
    await fulfillment(of: [loader.started(at: 1)], timeout: 1)
    let completion = loadCompletion(for: store)

    loader.succeed(1, with: completeHistory(solar: 6))
    await fulfillment(of: [completion.expectation], timeout: 1)
    loader.succeed(0, with: completeHistory(solar: 2))
    await fulfillment(of: [loader.finished(at: 0)], timeout: 1)

    XCTAssertEqual(
      store.flowHistory.readings.first(where: {
        $0.series == .pvGeneration
      })?.kilowatts,
      6
    )
    withExtendedLifetime(completion.subscription) {}
  }

  func testPendingRequestDoesNotRetainFlowStore() async {
    let loader = ControlledFlowHistoryLoader(requestCount: 1)
    var store: HomeEnergyFlowHistoryStore? = HomeEnergyFlowHistoryStore(
      loader: loader
    )
    weak let weakStore = store
    store?.reload()
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)

    store = nil

    XCTAssertNil(weakStore)
    loader.fail(0, with: CancellationError())
  }

  func testLoadFailurePreservesExistingFlowHistoryAsStale() async {
    let history = completeHistory()
    let loader = ControlledFlowHistoryLoader(requestCount: 1)
    let store = HomeEnergyFlowHistoryStore(
      loader: loader,
      flowHistory: history
    )
    store.reload()
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    let completion = loadCompletion(for: store)

    loader.fail(0, with: FlowHistoryStoreTestError.failed)
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertEqual(store.flowHistory, history)
    XCTAssertTrue(store.hasUsableHistory)
    XCTAssertTrue(store.isStale)
    XCTAssertFalse(store.isUnavailable)
    XCTAssertEqual(store.problem, .loadFailed)
    withExtendedLifetime(completion.subscription) {}
  }

  func testPendingLoadPreservesRapidFlowAvailabilityTransitions() async {
    let remote = completeHistory()
    let loader = ControlledFlowHistoryLoader(requestCount: 1)
    let store = HomeEnergyFlowHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    let firstLive = remote.interval.end.addingTimeInterval(1)

    store.record(
      snapshot: snapshot(solar: 8, home: 2, grid: -2, battery: -4),
      at: firstLive
    )
    store.record(
      snapshot: snapshot(solar: 8, home: 2, grid: nil, battery: -4),
      at: firstLive.addingTimeInterval(1)
    )
    store.record(
      snapshot: snapshot(solar: 8, home: 2, grid: 1, battery: -4),
      at: firstLive.addingTimeInterval(2)
    )
    let completion = loadCompletion(for: store)
    loader.succeed(0, with: remote)
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertEqual(
      store.flowHistory.readings.filter {
        $0.series == .grid && $0.timestamp >= firstLive
      },
      [
        .init(series: .grid, timestamp: firstLive, kilowatts: -2),
        .init(
          series: .grid,
          timestamp: firstLive.addingTimeInterval(1),
          kilowatts: nil
        ),
        .init(
          series: .grid,
          timestamp: firstLive.addingTimeInterval(2),
          kilowatts: 1
        ),
      ]
    )
    withExtendedLifetime(completion.subscription) {}
  }

  func testReloadPublishesCompleteFlowHistory() async {
    let history = completeHistory()
    let store = HomeEnergyFlowHistoryStore(
      loader: StaticFlowHistoryLoader(history: history)
    )
    let completed = expectation(description: "Flow history load completed")
    let subscription = store.$isLoading
      .dropFirst()
      .filter { !$0 }
      .prefix(1)
      .sink { _ in completed.fulfill() }

    store.reload()
    await fulfillment(of: [completed], timeout: 1)

    XCTAssertEqual(store.flowHistory.interval, history.interval)
    XCTAssertEqual(
      Dictionary(
        uniqueKeysWithValues: store.flowHistory.readings.compactMap { reading in
          reading.kilowatts.map { (reading.series, $0) }
        }
      ),
      [
        .pvGeneration: 8,
        .homeUsage: 2,
        .grid: -2,
        .battery: -4,
      ]
    )
    XCTAssertTrue(store.hasUsableHistory)
    XCTAssertFalse(store.isUnavailable)
    withExtendedLifetime(subscription) {}
  }

  func testIncompleteReloadKeepsExistingHistoryAsStale() async {
    let history = completeHistory()
    let incomplete = HomeEnergyFlowHistory(
      interval: history.interval,
      readings: history.readings.filter { $0.series != .battery }
    )
    let store = HomeEnergyFlowHistoryStore(
      loader: StaticFlowHistoryLoader(history: incomplete),
      flowHistory: history
    )
    let completed = expectation(description: "Incomplete flow history load completed")
    let subscription = store.$isLoading
      .dropFirst()
      .filter { !$0 }
      .prefix(1)
      .sink { _ in completed.fulfill() }

    store.reload()
    await fulfillment(of: [completed], timeout: 1)

    XCTAssertEqual(store.flowHistory, history)
    XCTAssertTrue(store.hasUsableHistory)
    XCTAssertTrue(store.isStale)
    withExtendedLifetime(subscription) {}
  }

  func testLiveFlowHistoryCoalescesUpdatesToGraphResolution() {
    let history = completeHistory()
    let end = history.interval.end
    let store = HomeEnergyFlowHistoryStore(
      loader: StaticFlowHistoryLoader(history: .empty),
      flowHistory: history
    )

    store.record(
      snapshot: snapshot(solar: 8.1, home: 2.1, grid: -2, battery: -4),
      at: end.addingTimeInterval(1)
    )
    store.record(
      snapshot: snapshot(solar: 8.2, home: 2.2, grid: -2, battery: -4),
      at: end.addingTimeInterval(2)
    )
    XCTAssertEqual(store.flowHistory, history)

    let sampleTimestamp = end.addingTimeInterval(HomeEnergyHistorySampling.interval)
    store.record(
      snapshot: snapshot(solar: 8.3, home: 2.3, grid: -2, battery: -4),
      at: sampleTimestamp
    )

    XCTAssertEqual(store.flowHistory.interval.end, sampleTimestamp)
    XCTAssertEqual(
      store.flowHistory.readings.last(where: { $0.series == .pvGeneration })?
        .kilowatts,
      8.3
    )
    XCTAssertEqual(
      store.flowHistory.readings.last(where: { $0.series == .homeUsage })?
        .kilowatts,
      2.3
    )
  }

  private func loadCompletion(
    for store: HomeEnergyFlowHistoryStore
  ) -> (expectation: XCTestExpectation, subscription: AnyCancellable) {
    let expectation = expectation(description: "Flow history load completed")
    let subscription = store.$isLoading
      .dropFirst()
      .filter { !$0 }
      .prefix(1)
      .sink { _ in expectation.fulfill() }
    return (expectation, subscription)
  }

  private func completeHistory(solar: Double = 8) -> HomeEnergyFlowHistory {
    let start = Date(timeIntervalSince1970: 100_000)
    let end = start.addingTimeInterval(24 * 60 * 60)
    return HomeEnergyFlowHistory(
      interval: DateInterval(start: start, end: end),
      readings: [
        .init(series: .pvGeneration, timestamp: start, kilowatts: solar),
        .init(series: .homeUsage, timestamp: start, kilowatts: 2),
        .init(series: .grid, timestamp: start, kilowatts: -2),
        .init(series: .battery, timestamp: start, kilowatts: -4),
      ]
    )
  }

  private func snapshot(
    solar: Double?,
    home: Double?,
    grid: Double?,
    battery: Double?
  ) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: solar,
      batteryStateOfCharge: nil,
      batteryPowerKilowatts: battery,
      homeConsumptionKilowatts: home,
      gridPowerKilowatts: grid,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil
    )
  }
}

private struct StaticFlowHistoryLoader: HomeAssistantHomeEnergyLoading {
  let history: HomeEnergyFlowHistory

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }

  func loadHomeEnergyFlowHistory() async throws -> HomeEnergyFlowHistory {
    history
  }
}

private final class ControlledFlowHistoryLoader:
  HomeAssistantHomeEnergyLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private let startedExpectations: [XCTestExpectation]
  private let finishedExpectations: [XCTestExpectation]
  private var nextRequest = 0
  private var continuations: [Int: CheckedContinuation<HomeEnergyFlowHistory, any Error>] = [:]

  init(requestCount: Int) {
    startedExpectations = (0..<requestCount).map {
      XCTestExpectation(description: "Flow history load \($0) started")
    }
    finishedExpectations = (0..<requestCount).map {
      XCTestExpectation(description: "Flow history load \($0) finished")
    }
  }

  func started(at index: Int) -> XCTestExpectation {
    startedExpectations[index]
  }

  func finished(at index: Int) -> XCTestExpectation {
    finishedExpectations[index]
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }

  func loadHomeEnergyFlowHistory() async throws -> HomeEnergyFlowHistory {
    let request = lock.withLock {
      let request = nextRequest
      nextRequest += 1
      return request
    }
    defer {
      finishedExpectations[request].fulfill()
    }
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        continuations[request] = continuation
      }
      startedExpectations[request].fulfill()
    }
  }

  func succeed(_ request: Int, with history: HomeEnergyFlowHistory) {
    let continuation = lock.withLock {
      continuations.removeValue(forKey: request)
    }
    continuation?.resume(returning: history)
  }

  func fail(_ request: Int, with error: any Error) {
    let continuation = lock.withLock {
      continuations.removeValue(forKey: request)
    }
    continuation?.resume(throwing: error)
  }
}

private enum FlowHistoryStoreTestError: Error {
  case failed
}

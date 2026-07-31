import XCTest

@testable import Bruce

final class DailyEnergyStreamTests: XCTestCase {
  func testIrrelevantStateBurstDoesNotRepeatDailyTotalsRequest() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let source = ControlledStateSource()
    let totalsLoader = RecordingDailyEnergyTotalsLoader(
      totals: totals(
        importCost: 0.20,
        earnings: 0.91,
        start: timestamp.addingTimeInterval(-60),
        end: timestamp.addingTimeInterval(24 * 60 * 60)
      )
    )
    let stream = HomeAssistantHomeEnergyStream(
      states: HomeAssistantStateHub(source: source),
      loader: UnusedDailyTotalsHomeEnergyLoader(),
      dailyTotalsLoader: totalsLoader,
      now: { timestamp }
    )
    let probe = AsyncThrowingStreamTestProbe(stream.homeEnergyUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(
      .live(
        try states(
          solar: 8.4,
          importCostCounter: 2,
          earningsCounter: 4
        )
      )
    )
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let initial = try liveSnapshot(probe.value(at: 1))

    for index in 1...50 {
      source.yield(
        .live(
          try states(
            solar: 8.4 + Double(index) / 10,
            importCostCounter: 2 + Double(index) / 10_000,
            earningsCounter: 4 + Double(index) / 10_000
          )
        )
      )
    }
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    XCTAssertEqual(initial.importCostTodayDollars, 0.20)
    XCTAssertEqual(initial.feedInEarningsTodayDollars, 0.91)
    XCTAssertEqual(totalsLoader.requestCount, 1)
  }

  func testCounterResetImmediatelyReloadsAuthoritativeTotals() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let source = ControlledStateSource()
    let totalsLoader = RecordingDailyEnergyTotalsLoader(
      totals: restartTotals(at: timestamp)
    )
    let stream = HomeAssistantHomeEnergyStream(
      states: HomeAssistantStateHub(source: source),
      loader: UnusedDailyTotalsHomeEnergyLoader(),
      dailyTotalsLoader: totalsLoader,
      now: { timestamp }
    )
    let probe = AsyncThrowingStreamTestProbe(stream.homeEnergyUpdates())
    await fulfillment(of: [source.started], timeout: 1)
    source.yield(
      .live(
        try states(
          solar: 8.4,
          importCostCounter: 2,
          earningsCounter: 4,
          lastReset: "before-restart"
        )
      )
    )
    await fulfillment(
      of: [probe.received(at: 0), probe.received(at: 1)],
      timeout: 1
    )

    source.yield(
      .live(
        try states(
          solar: 8.4,
          importCostCounter: 0,
          earningsCounter: 0,
          lastReset: "after-restart"
        )
      )
    )
    await fulfillment(
      of: [probe.received(at: 2), probe.received(at: 3)],
      timeout: 1
    )
    let refreshed = try liveSnapshot(probe.value(at: 3))

    XCTAssertEqual(refreshed.importCostTodayDollars, 0.24)
    XCTAssertEqual(refreshed.feedInEarningsTodayDollars, 0.98)
    XCTAssertEqual(totalsLoader.requestCount, 2)
  }

  func testRegularEnergySnapshotArrivesBeforeDailyTotalsRequestFinishes() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let source = ControlledStateSource()
    let totalsLoader = SuspendedDailyEnergyTotalsLoader(
      totals: totals(
        importCost: 0.20,
        earnings: 0.91,
        start: timestamp.addingTimeInterval(-60),
        end: timestamp.addingTimeInterval(24 * 60 * 60)
      )
    )
    let stream = HomeAssistantHomeEnergyStream(
      states: HomeAssistantStateHub(source: source),
      loader: UnusedDailyTotalsHomeEnergyLoader(),
      dailyTotalsLoader: totalsLoader,
      now: { timestamp }
    )
    let probe = AsyncThrowingStreamTestProbe(stream.homeEnergyUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(
      .live(
        try states(
          solar: 8.4,
          importCostCounter: 2,
          earningsCounter: 4
        )
      )
    )
    await fulfillment(of: [totalsLoader.started], timeout: 1)
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let immediate = try liveSnapshot(probe.value(at: 0))

    XCTAssertEqual(immediate.pvPowerKilowatts, 8.4)
    XCTAssertNil(immediate.importCostTodayDollars)
    XCTAssertEqual(immediate.importCostTodayStatus, .refreshing)

    source.yield(
      .live(
        try states(
          solar: 9.1,
          importCostCounter: 2,
          earningsCounter: 4
        )
      )
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let whileLoading = try liveSnapshot(probe.value(at: 1))
    XCTAssertEqual(whileLoading.pvPowerKilowatts, 9.1)
    XCTAssertEqual(whileLoading.importCostTodayStatus, .refreshing)

    totalsLoader.resume()
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)
    let refreshed = try liveSnapshot(probe.value(at: 2))
    XCTAssertEqual(refreshed.importCostTodayDollars, 0.20)
  }

  func testFailureBackoffStartsWhenSlowRequestFinishes() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = DailyEnergyTestClock(timestamp)
    let source = ControlledStateSource()
    let totalsLoader = AdvancingFailingDailyTotalsLoader(clock: clock)
    let stream = HomeAssistantHomeEnergyStream(
      states: HomeAssistantStateHub(source: source),
      loader: UnusedDailyTotalsHomeEnergyLoader(),
      dailyTotalsLoader: totalsLoader,
      now: { clock.now }
    )
    let probe = AsyncThrowingStreamTestProbe(stream.homeEnergyUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(
      .live(
        try states(
          solar: 8.4,
          importCostCounter: 2,
          earningsCounter: 4
        )
      )
    )
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    source.yield(
      .live(
        try states(
          solar: 8.5,
          importCostCounter: 2,
          earningsCounter: 4
        )
      )
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)

    XCTAssertEqual(totalsLoader.requestCount, 1)
  }

  private func liveSnapshot(
    _ update: HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>?
  ) throws -> HomeAssistantHomeEnergySnapshot {
    guard case .live(let snapshot) = try XCTUnwrap(update) else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return snapshot
  }

  private func states(
    solar: Double,
    importCostCounter: Double,
    earningsCounter: Double,
    lastReset: String = "initial"
  ) throws -> [HomeAssistantState] {
    try JSONDecoder().decode(
      [HomeAssistantState].self,
      from: Data(
        """
        [
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.pvPowerEntityID)",
            "state":"\(solar)",
            "attributes":{}
          },
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.importCostEntityID)",
            "state":"\(importCostCounter)",
            "attributes":{"last_reset":"\(lastReset)"}
          },
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID)",
            "state":"\(earningsCounter)",
            "attributes":{"last_reset":"\(lastReset)"}
          }
        ]
        """.utf8
      )
    )
  }

}

extension DailyEnergyStreamTests {
  fileprivate func totals(
    importCost: Double,
    earnings: Double,
    start: Date,
    end: Date,
    importCounter: Double? = nil,
    earningsCounter: Double? = nil
  ) -> HomeAssistantDailyEnergyTotals {
    HomeAssistantDailyEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: earnings,
      interval: DateInterval(start: start, end: end),
      importCounter: importCounter.map {
        HomeAssistantEnergyCounterReference(value: $0, lastReset: nil)
      },
      feedInCounter: earningsCounter.map {
        HomeAssistantEnergyCounterReference(value: $0, lastReset: nil)
      }
    )
  }

  fileprivate func restartTotals(
    at timestamp: Date
  ) -> [HomeAssistantDailyEnergyTotals] {
    [
      totals(
        importCost: 0.20,
        earnings: 0.91,
        start: timestamp.addingTimeInterval(-60),
        end: timestamp.addingTimeInterval(24 * 60 * 60)
      ),
      totals(
        importCost: 0.24,
        earnings: 0.98,
        start: timestamp.addingTimeInterval(-60),
        end: timestamp.addingTimeInterval(24 * 60 * 60),
        importCounter: 0,
        earningsCounter: 0
      ),
    ]
  }
}

private final class RecordingDailyEnergyTotalsLoader:
  HomeAssistantDailyEnergyTotalsLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var totals: [HomeAssistantDailyEnergyTotals]
  private var storedRequestCount = 0

  init(totals: HomeAssistantDailyEnergyTotals) {
    self.totals = [totals]
  }

  init(totals: [HomeAssistantDailyEnergyTotals]) {
    self.totals = totals
  }

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func loadDailyEnergyTotals() async throws -> HomeAssistantDailyEnergyTotals {
    try lock.withLock {
      storedRequestCount += 1
      guard !totals.isEmpty else {
        throw HomeAssistantAPIError.invalidResponse
      }
      return totals.removeFirst()
    }
  }
}

private final class SuspendedDailyEnergyTotalsLoader:
  HomeAssistantDailyEnergyTotalsLoading, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Daily energy totals request started")

  private let totals: HomeAssistantDailyEnergyTotals
  private let lock = NSLock()
  private var continuation: CheckedContinuation<HomeAssistantDailyEnergyTotals, Never>?

  init(totals: HomeAssistantDailyEnergyTotals) {
    self.totals = totals
  }

  func loadDailyEnergyTotals() async -> HomeAssistantDailyEnergyTotals {
    await withCheckedContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func resume() {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(returning: totals)
  }
}

private final class DailyEnergyTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var storedNow: Date

  init(_ now: Date) {
    storedNow = now
  }

  var now: Date {
    lock.withLock { storedNow }
  }

  func advance(by interval: TimeInterval) {
    lock.withLock {
      storedNow = storedNow.addingTimeInterval(interval)
    }
  }
}

private final class AdvancingFailingDailyTotalsLoader:
  HomeAssistantDailyEnergyTotalsLoading, @unchecked Sendable
{
  private let clock: DailyEnergyTestClock
  private let lock = NSLock()
  private var storedRequestCount = 0

  init(clock: DailyEnergyTestClock) {
    self.clock = clock
  }

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func loadDailyEnergyTotals() async throws -> HomeAssistantDailyEnergyTotals {
    lock.withLock {
      storedRequestCount += 1
    }
    clock.advance(by: HomeAssistantDailyEnergyRefreshState.failureRetryInterval + 1)
    throw URLError(.timedOut)
  }
}

private struct UnusedDailyTotalsHomeEnergyLoader:
  HomeAssistantHomeEnergyLoading
{
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw HomeAssistantAPIError.invalidResponse
  }
}

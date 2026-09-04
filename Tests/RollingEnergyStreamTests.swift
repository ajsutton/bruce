import XCTest

@testable import Bruce

final class RollingEnergyStreamTests: XCTestCase {
  func testIrrelevantStateBurstDoesNotRepeatRollingTotalsRequest() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let source = ControlledStateSource()
    let totalsLoader = RecordingRollingEnergyTotalsLoader(
      totals: totals(
        importCost: 0.20,
        earnings: 0.91,
        end: timestamp.addingTimeInterval(24 * 60 * 60)
      )
    )
    let stream = HomeAssistantHomeEnergyStream(
      states: HomeAssistantStateHub(source: source),
      loader: UnusedRollingTotalsHomeEnergyLoader(),
      rollingTotalsLoader: totalsLoader,
      now: { timestamp }
    )
    let probe = AsyncThrowingStreamTestProbe(stream.homeEnergyUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(
      .live(
        try states(solar: 8.4)
      )
    )
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let initial = try liveSnapshot(probe.value(at: 1))

    for index in 1...50 {
      source.yield(
        .live(
          try states(solar: 8.4 + Double(index) / 10)
        )
      )
    }
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    XCTAssertEqual(initial.importCostLast24HoursDollars, 0.20)
    XCTAssertEqual(initial.feedInEarningsLast24HoursDollars, 0.91)
    XCTAssertEqual(totalsLoader.requestCount, 1)
  }

  func testRegularEnergySnapshotArrivesBeforeRollingTotalsRequestFinishes() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let source = ControlledStateSource()
    let totalsLoader = SuspendedRollingEnergyTotalsLoader(
      totals: totals(
        importCost: 0.20,
        earnings: 0.91,
        end: timestamp.addingTimeInterval(24 * 60 * 60)
      )
    )
    let stream = HomeAssistantHomeEnergyStream(
      states: HomeAssistantStateHub(source: source),
      loader: UnusedRollingTotalsHomeEnergyLoader(),
      rollingTotalsLoader: totalsLoader,
      now: { timestamp }
    )
    let probe = AsyncThrowingStreamTestProbe(stream.homeEnergyUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(
      .live(
        try states(solar: 8.4)
      )
    )
    await fulfillment(of: [totalsLoader.started], timeout: 1)
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let immediate = try liveSnapshot(probe.value(at: 0))

    XCTAssertEqual(immediate.pvPowerKilowatts, 8.4)
    XCTAssertNil(immediate.importCostLast24HoursDollars)
    XCTAssertEqual(immediate.importCostLast24HoursStatus, .refreshing)

    source.yield(
      .live(
        try states(solar: 9.1)
      )
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let whileLoading = try liveSnapshot(probe.value(at: 1))
    XCTAssertEqual(whileLoading.pvPowerKilowatts, 9.1)
    XCTAssertEqual(whileLoading.importCostLast24HoursStatus, .refreshing)

    totalsLoader.resume()
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)
    let refreshed = try liveSnapshot(probe.value(at: 2))
    XCTAssertEqual(refreshed.importCostLast24HoursDollars, 0.20)
  }

  func testFailureBackoffStartsWhenSlowRequestFinishes() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = RollingEnergyTestClock(timestamp)
    let source = ControlledStateSource()
    let totalsLoader = AdvancingFailingRollingTotalsLoader(clock: clock)
    let stream = HomeAssistantHomeEnergyStream(
      states: HomeAssistantStateHub(source: source),
      loader: UnusedRollingTotalsHomeEnergyLoader(),
      rollingTotalsLoader: totalsLoader,
      now: { clock.now }
    )
    let probe = AsyncThrowingStreamTestProbe(stream.homeEnergyUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(
      .live(
        try states(solar: 8.4)
      )
    )
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    source.yield(
      .live(
        try states(solar: 8.5)
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

  private func states(solar: Double) throws -> [HomeAssistantState] {
    try JSONDecoder().decode(
      [HomeAssistantState].self,
      from: Data(
        """
        [
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.pvPowerEntityID)",
            "state":"\(solar)",
            "attributes":{}
          }
        ]
        """.utf8
      )
    )
  }

}

extension RollingEnergyStreamTests {
  fileprivate func totals(
    importCost: Double,
    earnings: Double,
    end: Date
  ) -> HomeAssistantRollingEnergyTotals {
    HomeAssistantRollingEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: earnings,
      refreshAfter: end
    )
  }
}

private final class RecordingRollingEnergyTotalsLoader:
  HomeAssistantRollingEnergyTotalsLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var totals: [HomeAssistantRollingEnergyTotals]
  private var storedRequestCount = 0

  init(totals: HomeAssistantRollingEnergyTotals) {
    self.totals = [totals]
  }

  init(totals: [HomeAssistantRollingEnergyTotals]) {
    self.totals = totals
  }

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func loadRollingEnergyTotals() async throws -> HomeAssistantRollingEnergyTotals {
    try lock.withLock {
      storedRequestCount += 1
      guard !totals.isEmpty else {
        throw HomeAssistantAPIError.invalidResponse
      }
      return totals.removeFirst()
    }
  }
}

private final class SuspendedRollingEnergyTotalsLoader:
  HomeAssistantRollingEnergyTotalsLoading, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Rolling energy totals request started")

  private let totals: HomeAssistantRollingEnergyTotals
  private let lock = NSLock()
  private var continuation: CheckedContinuation<HomeAssistantRollingEnergyTotals, Never>?

  init(totals: HomeAssistantRollingEnergyTotals) {
    self.totals = totals
  }

  func loadRollingEnergyTotals() async -> HomeAssistantRollingEnergyTotals {
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

private final class RollingEnergyTestClock: @unchecked Sendable {
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

private final class AdvancingFailingRollingTotalsLoader:
  HomeAssistantRollingEnergyTotalsLoading, @unchecked Sendable
{
  private let clock: RollingEnergyTestClock
  private let lock = NSLock()
  private var storedRequestCount = 0

  init(clock: RollingEnergyTestClock) {
    self.clock = clock
  }

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func loadRollingEnergyTotals() async throws -> HomeAssistantRollingEnergyTotals {
    lock.withLock {
      storedRequestCount += 1
    }
    clock.advance(by: HomeAssistantRollingEnergyRefreshState.failureRetryInterval + 1)
    throw URLError(.timedOut)
  }
}

private struct UnusedRollingTotalsHomeEnergyLoader:
  HomeAssistantHomeEnergyLoading
{
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw HomeAssistantAPIError.invalidResponse
  }
}

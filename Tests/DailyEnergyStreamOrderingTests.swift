import XCTest

@testable import Bruce

final class DailyEnergyStreamOrderingTests: XCTestCase {
  func testFirstAuthoritativeUpdateIncludesRecorderLagAdjustment() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let source = ControlledStateSource()
    let loader = ImmediateOrderingDailyTotalsLoader(
      totals: totals(
        importCost: 0.20,
        earnings: 0.91,
        start: timestamp,
        end: timestamp.addingTimeInterval(300),
        importCounter: 1.995,
        earningsCounter: 3.99
      )
    )
    let probe = AsyncThrowingStreamTestProbe(
      stream(source: source, loader: loader, now: { timestamp })
    )
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(
      .live(
        try states(
          importCostCounter: 2,
          earningsCounter: 4,
          lastReset: nil
        )
      )
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let refreshed = try liveSnapshot(probe.value(at: 1))

    XCTAssertEqual(
      try XCTUnwrap(refreshed.importCostTodayDollars),
      0.205,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      try XCTUnwrap(refreshed.feedInEarningsTodayDollars),
      0.92,
      accuracy: 0.000_001
    )
  }

  func testResetReplacesInFlightRequestAndUsesLatestLiveSnapshot()
    async throws
  {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let oldReset = Date(timeIntervalSince1970: 1)
    let newReset = Date(timeIntervalSince1970: 2)
    let source = ControlledStateSource()
    let loader = ReplacingOrderingDailyTotalsLoader()
    let probe = AsyncThrowingStreamTestProbe(
      stream(source: source, loader: loader, now: { timestamp })
    )
    let originalStates = try states(
      importCostCounter: 2,
      earningsCounter: 4,
      lastReset: oldReset
    )
    let resetStates = try states(
      importCostCounter: 0.001,
      earningsCounter: 0.002,
      lastReset: newReset
    )
    await fulfillment(of: [source.started], timeout: 1)
    source.yield(.live(originalStates))
    await fulfillment(
      of: [loader.started(at: 0), probe.received(at: 0)],
      timeout: 1
    )

    source.yield(.live(resetStates))
    await fulfillment(
      of: [loader.started(at: 1), probe.received(at: 1)],
      timeout: 1
    )
    loader.resume(
      request: 1,
      with: resetTotals(timestamp: timestamp, reset: newReset)
    )
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)
    let caughtUp = try liveSnapshot(probe.value(at: 2))

    XCTAssertEqual(loader.requestCount, 2)
    XCTAssertEqual(
      try XCTUnwrap(caughtUp.importCostTodayDollars),
      0.241,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      try XCTUnwrap(caughtUp.feedInEarningsTodayDollars),
      0.982,
      accuracy: 0.000_001
    )
  }

  func testExpiredResultRetriesOnceWithoutPublishingExpiredTotal()
    async throws
  {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = OrderingDailyEnergyClock(timestamp)
    let source = ControlledStateSource()
    let loader = AdvancingOrderingDailyTotalsLoader(
      clock: clock,
      totals: totals(
        importCost: 0.20,
        earnings: 0.91,
        start: timestamp,
        end: timestamp.addingTimeInterval(1)
      )
    )
    let probe = AsyncThrowingStreamTestProbe(
      stream(source: source, loader: loader, now: { clock.now })
    )
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(
      .live(
        try states(
          importCostCounter: 2,
          earningsCounter: 4,
          lastReset: nil
        )
      )
    )
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)
    let completed = try liveSnapshot(probe.value(at: 2))

    XCTAssertNil(completed.importCostTodayDollars)
    XCTAssertNil(completed.feedInEarningsTodayDollars)
    XCTAssertEqual(completed.importCostTodayStatus, .failed)
    XCTAssertEqual(loader.requestCount, 2)
  }

  private func stream(
    source: ControlledStateSource,
    loader: any HomeAssistantDailyEnergyTotalsLoading,
    now: @escaping @Sendable () -> Date
  ) -> HomeAssistantHomeEnergyUpdateStream {
    HomeAssistantHomeEnergyStream(
      states: HomeAssistantStateHub(source: source),
      loader: OrderingUnusedHomeEnergyLoader(),
      dailyTotalsLoader: loader,
      now: now
    ).homeEnergyUpdates()
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
    importCostCounter: Double,
    earningsCounter: Double,
    lastReset: Date?
  ) throws -> [HomeAssistantState] {
    let lastResetJSON =
      lastReset.map {
        "\"\($0.formatted(.iso8601))\""
      } ?? "null"
    return try JSONDecoder().decode(
      [HomeAssistantState].self,
      from: Data(
        """
        [
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.pvPowerEntityID)",
            "state":"8.4",
            "attributes":{}
          },
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.importCostEntityID)",
            "state":"\(importCostCounter)",
            "attributes":{"last_reset":\(lastResetJSON)}
          },
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID)",
            "state":"\(earningsCounter)",
            "attributes":{"last_reset":\(lastResetJSON)}
          }
        ]
        """.utf8
      )
    )
  }

  private func totals(
    importCost: Double,
    earnings: Double,
    start: Date,
    end: Date,
    importCounter: Double? = nil,
    earningsCounter: Double? = nil,
    lastReset: Date? = nil
  ) -> HomeAssistantDailyEnergyTotals {
    HomeAssistantDailyEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: earnings,
      interval: DateInterval(start: start, end: end),
      importCounter: importCounter.map {
        HomeAssistantEnergyCounterReference(value: $0, lastReset: lastReset)
      },
      feedInCounter: earningsCounter.map {
        HomeAssistantEnergyCounterReference(value: $0, lastReset: lastReset)
      }
    )
  }

  private func resetTotals(
    timestamp: Date,
    reset: Date
  ) -> HomeAssistantDailyEnergyTotals {
    totals(
      importCost: 0.24,
      earnings: 0.98,
      start: timestamp,
      end: timestamp.addingTimeInterval(300),
      importCounter: 0,
      earningsCounter: 0,
      lastReset: reset
    )
  }

}

private struct OrderingUnusedHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw HomeAssistantAPIError.invalidResponse
  }
}

private struct ImmediateOrderingDailyTotalsLoader:
  HomeAssistantDailyEnergyTotalsLoading
{
  let totals: HomeAssistantDailyEnergyTotals

  func loadDailyEnergyTotals() async -> HomeAssistantDailyEnergyTotals {
    totals
  }
}

private final class ReplacingOrderingDailyTotalsLoader:
  HomeAssistantDailyEnergyTotalsLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private let startedExpectations = (0..<2).map {
    XCTestExpectation(description: "Ordering totals request \($0) started")
  }
  private var continuations: [Int: CheckedContinuation<HomeAssistantDailyEnergyTotals, any Error>] =
    [:]
  private var cancelledRequests: Set<Int> = []
  private var storedRequestCount = 0

  func started(at request: Int) -> XCTestExpectation {
    startedExpectations[request]
  }

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func loadDailyEnergyTotals() async throws -> HomeAssistantDailyEnergyTotals {
    let request = lock.withLock {
      let request = storedRequestCount
      storedRequestCount += 1
      return request
    }
    startedExpectations[request].fulfill()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let wasCancelled = lock.withLock {
          if cancelledRequests.contains(request) {
            return true
          }
          continuations[request] = continuation
          return false
        }
        if wasCancelled {
          continuation.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      let continuation = self.lock.withLock {
        self.cancelledRequests.insert(request)
        return self.continuations.removeValue(forKey: request)
      }
      continuation?.resume(throwing: CancellationError())
    }
  }

  func resume(
    request: Int,
    with totals: HomeAssistantDailyEnergyTotals
  ) {
    let continuation = lock.withLock {
      continuations.removeValue(forKey: request)
    }
    continuation?.resume(returning: totals)
  }
}

private final class OrderingDailyEnergyClock: @unchecked Sendable {
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

private final class AdvancingOrderingDailyTotalsLoader:
  HomeAssistantDailyEnergyTotalsLoading, @unchecked Sendable
{
  let clock: OrderingDailyEnergyClock
  let totals: HomeAssistantDailyEnergyTotals
  private let lock = NSLock()
  private var storedRequestCount = 0

  init(
    clock: OrderingDailyEnergyClock,
    totals: HomeAssistantDailyEnergyTotals
  ) {
    self.clock = clock
    self.totals = totals
  }

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func loadDailyEnergyTotals() async -> HomeAssistantDailyEnergyTotals {
    lock.withLock {
      storedRequestCount += 1
    }
    clock.advance(by: 2)
    return totals
  }
}

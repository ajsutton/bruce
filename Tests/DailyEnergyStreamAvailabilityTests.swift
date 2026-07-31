import XCTest

@testable import Bruce

final class DailyEnergyStreamAvailabilityTests: XCTestCase {
  func testCounterReturningAfterGapIsHiddenUntilRefresh() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let source = ControlledStateSource()
    let loader = AvailabilityDailyTotalsLoader(
      totals: [
        totals(importCost: 0.20, at: timestamp),
        totals(importCost: 0.24, at: timestamp),
      ]
    )
    let stream = HomeAssistantHomeEnergyStream(
      states: HomeAssistantStateHub(source: source),
      loader: AvailabilityUnusedHomeEnergyLoader(),
      dailyTotalsLoader: loader,
      now: { timestamp }
    )
    let probe = AsyncThrowingStreamTestProbe(stream.homeEnergyUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(.live(try states(importCostCounter: "2")))
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    source.yield(.live(try states(importCostCounter: "unavailable")))
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)
    source.yield(.live(try states(importCostCounter: "3")))
    await fulfillment(of: [probe.received(at: 3)], timeout: 1)
    let refreshing = try liveSnapshot(probe.value(at: 3))

    XCTAssertNil(refreshing.importCostTodayDollars)
    XCTAssertEqual(refreshing.importCostTodayStatus, .refreshing)
    XCTAssertEqual(refreshing.feedInEarningsTodayDollars, 0.91)
    XCTAssertEqual(refreshing.feedInEarningsTodayStatus, .current)
    await fulfillment(of: [probe.received(at: 4)], timeout: 1)
    XCTAssertEqual(loader.requestCount, 2)
  }

  private func states(
    importCostCounter: String
  ) throws -> [HomeAssistantState] {
    try JSONDecoder().decode(
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
            "attributes":{"last_reset":"initial"}
          },
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID)",
            "state":"4",
            "attributes":{"last_reset":"initial"}
          }
        ]
        """.utf8
      )
    )
  }

  private func totals(
    importCost: Double,
    at timestamp: Date
  ) -> HomeAssistantDailyEnergyTotals {
    HomeAssistantDailyEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: 0.91,
      interval: DateInterval(
        start: timestamp.addingTimeInterval(-60),
        end: timestamp.addingTimeInterval(24 * 60 * 60)
      )
    )
  }

  private func liveSnapshot(
    _ update: HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>?
  ) throws -> HomeAssistantHomeEnergySnapshot {
    guard case .live(let snapshot) = try XCTUnwrap(update) else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return snapshot
  }
}

private final class AvailabilityDailyTotalsLoader:
  HomeAssistantDailyEnergyTotalsLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var totals: [HomeAssistantDailyEnergyTotals]
  private var storedRequestCount = 0

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

private struct AvailabilityUnusedHomeEnergyLoader:
  HomeAssistantHomeEnergyLoading
{
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw HomeAssistantAPIError.invalidResponse
  }
}

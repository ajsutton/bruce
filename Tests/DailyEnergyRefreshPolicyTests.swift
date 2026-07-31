import XCTest

@testable import Bruce

final class DailyEnergyRefreshPolicyTests: XCTestCase {
  func testLiveCountersAdjustTotalsWithoutAnotherStatisticsRequest() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    var state = HomeAssistantDailyEnergyRefreshState()
    let initial = snapshot(
      importCostCounter: 2,
      earningsCounter: 4,
      lastReset: 1
    )

    XCTAssertTrue(state.shouldRefresh(for: initial, at: start))
    state.noteSuccess(
      totals(
        importCost: 0.20,
        earnings: 0.91,
        start: start,
        end: start.addingTimeInterval(24 * 60 * 60)
      ),
      snapshot: initial
    )

    let updated = snapshot(
      importCostCounter: 2.006,
      earningsCounter: 4.011,
      lastReset: 1
    )
    let adjusted = try XCTUnwrap(
      state.totals(
        adjustedFor: updated,
        at: start.addingTimeInterval(1)
      )
    )

    XCTAssertFalse(
      state.shouldRefresh(for: updated, at: start.addingTimeInterval(1))
    )
    XCTAssertEqual(
      try XCTUnwrap(adjusted.importCostDollars),
      0.206,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      try XCTUnwrap(adjusted.feedInEarningsDollars),
      0.921,
      accuracy: 0.000_001
    )
  }

  func testStatisticsCounterStateAccountsForRecorderLag() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let lastReset = Date(timeIntervalSince1970: 1)
    let snapshot = snapshot(
      importCostCounter: 2,
      earningsCounter: 4,
      lastReset: 1
    )
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(
      HomeAssistantDailyEnergyTotals(
        importCostDollars: 0.20,
        feedInEarningsDollars: 0.91,
        interval: DateInterval(
          start: start,
          end: start.addingTimeInterval(24 * 60 * 60)
        ),
        importCounter: HomeAssistantEnergyCounterReference(
          value: 1.995,
          lastReset: lastReset
        ),
        feedInCounter: HomeAssistantEnergyCounterReference(
          value: 3.99,
          lastReset: lastReset
        )
      ),
      snapshot: snapshot
    )

    let adjusted = try XCTUnwrap(
      state.totals(
        adjustedFor: snapshot,
        at: start.addingTimeInterval(1)
      )
    )

    XCTAssertEqual(
      try XCTUnwrap(adjusted.importCostDollars),
      0.205,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      try XCTUnwrap(adjusted.feedInEarningsDollars),
      0.92,
      accuracy: 0.000_001
    )
  }

  func testControlTransitionCounterResetAndNewDayRequestAuthoritativeTotals() {
    let start = Date(timeIntervalSince1970: 1_000)
    let initial = snapshot(
      importCostCounter: 2,
      earningsCounter: 4,
      lastReset: 1
    )
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(
      totals(
        importCost: 0.20,
        earnings: 0.91,
        start: start,
        end: start.addingTimeInterval(300)
      ),
      snapshot: initial
    )

    XCTAssertTrue(
      state.shouldRefresh(
        for: snapshot(
          importCostCounter: 0,
          earningsCounter: 0,
          lastReset: 2
        ),
        at: start.addingTimeInterval(1)
      )
    )
    XCTAssertTrue(
      state.shouldRefresh(for: initial, at: start.addingTimeInterval(301))
    )
    state.noteControlTransition()
    XCTAssertTrue(
      state.shouldRefresh(for: initial, at: start.addingTimeInterval(1))
    )
  }

  func testFailedStatisticsRefreshBacksOffUnrelatedEvents() {
    let start = Date(timeIntervalSince1970: 1_000)
    let snapshot = snapshot(
      importCostCounter: 2,
      earningsCounter: 4,
      lastReset: 1
    )
    var state = HomeAssistantDailyEnergyRefreshState()

    state.noteFailure(at: start)

    XCTAssertFalse(
      state.shouldRefresh(for: snapshot, at: start.addingTimeInterval(299))
    )
    XCTAssertTrue(
      state.shouldRefresh(for: snapshot, at: start.addingTimeInterval(300))
    )
  }

  func testExactDailyIntervalEndRequiresRefreshAndHidesPriorTotal() {
    let start = Date(timeIntervalSince1970: 1_000)
    let end = start.addingTimeInterval(300)
    let snapshot = snapshot(
      importCostCounter: 2,
      earningsCounter: 4,
      lastReset: 1
    )
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(
      totals(
        importCost: 0.20,
        earnings: 0.91,
        start: start,
        end: end
      ),
      snapshot: snapshot
    )

    XCTAssertTrue(state.shouldRefresh(for: snapshot, at: end))
    XCTAssertNil(state.totals(adjustedFor: snapshot, at: end))
  }

  func testPartialStatisticsKeepValidSiblingAndRetryMissingTotal() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let snapshot = snapshot(
      importCostCounter: 2,
      earningsCounter: 4,
      lastReset: 1
    )
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(
      HomeAssistantDailyEnergyTotals(
        importCostDollars: 0.20,
        feedInEarningsDollars: nil,
        interval: DateInterval(
          start: start,
          end: start.addingTimeInterval(24 * 60 * 60)
        )
      ),
      snapshot: snapshot,
      at: start
    )

    let adjusted = try XCTUnwrap(
      state.totals(
        adjustedFor: snapshot,
        at: start.addingTimeInterval(1)
      )
    )
    XCTAssertEqual(adjusted.importCostDollars, 0.20)
    XCTAssertNil(adjusted.feedInEarningsDollars)
    XCTAssertFalse(
      state.shouldRefresh(for: snapshot, at: start.addingTimeInterval(299))
    )
    XCTAssertTrue(
      state.shouldRefresh(for: snapshot, at: start.addingTimeInterval(300))
    )
  }

  private func snapshot(
    importCostCounter: Double,
    earningsCounter: Double,
    lastReset: TimeInterval? = nil
  ) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.4,
      batteryStateOfCharge: nil,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostCounterDollars: importCostCounter,
      feedInEarningsCounterDollars: earningsCounter,
      importCostCounterLastReset: lastReset.map {
        Date(timeIntervalSince1970: $0)
      },
      feedInEarningsCounterLastReset: lastReset.map {
        Date(timeIntervalSince1970: $0)
      }
    )
  }

  private func totals(
    importCost: Double,
    earnings: Double,
    start: Date,
    end: Date
  ) -> HomeAssistantDailyEnergyTotals {
    HomeAssistantDailyEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: earnings,
      interval: DateInterval(start: start, end: end)
    )
  }
}

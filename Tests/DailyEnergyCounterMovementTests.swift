import XCTest

@testable import Bruce

final class DailyEnergyCounterMovementTests: XCTestCase {
  func testDecreasingCountersWithUnchangedResetMarkerUseSignedDeltas()
    throws
  {
    let start = Date(timeIntervalSince1970: 1_000)
    let reset = Date(timeIntervalSince1970: 1)
    let initial = snapshot(importCost: 2, earnings: 4, lastReset: reset)
    let decreased = snapshot(
      importCost: 1.99,
      earnings: 3.995,
      lastReset: reset
    )
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(totals(start: start), snapshot: initial)

    XCTAssertFalse(
      state.shouldRefresh(for: decreased, at: start.addingTimeInterval(1))
    )
    let adjusted = try XCTUnwrap(
      state.totals(
        adjustedFor: decreased,
        at: start.addingTimeInterval(1)
      )
    )
    XCTAssertEqual(
      try XCTUnwrap(adjusted.importCostDollars),
      0.19,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      try XCTUnwrap(adjusted.feedInEarningsDollars),
      0.905,
      accuracy: 0.000_001
    )
  }

  func testSingleCounterResetKeepsSiblingTotalVisible() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let reset = Date(timeIntervalSince1970: 1)
    let initial = snapshot(importCost: 2, earnings: 4, lastReset: reset)
    let restartedImport = snapshot(
      importCost: 0,
      earnings: 4.001,
      lastReset: reset
    )
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(totals(start: start), snapshot: initial)

    XCTAssertTrue(
      state.shouldRefresh(
        for: restartedImport,
        at: start.addingTimeInterval(1)
      )
    )
    let adjusted = try XCTUnwrap(
      state.totals(
        adjustedFor: restartedImport,
        at: start.addingTimeInterval(1)
      )
    )
    XCTAssertNil(adjusted.importCostDollars)
    XCTAssertEqual(
      try XCTUnwrap(adjusted.feedInEarningsDollars),
      0.911,
      accuracy: 0.000_001
    )
  }

  func testSingleCounterResetAtIntervalEndRefreshesBothMetrics() {
    let start = Date(timeIntervalSince1970: 1_000)
    let reset = Date(timeIntervalSince1970: 1)
    let initial = snapshot(importCost: 2, earnings: 4, lastReset: reset)
    let restartedImport = snapshot(
      importCost: 0,
      earnings: 4.001,
      lastReset: reset
    )
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(totals(start: start), snapshot: initial)

    XCTAssertTrue(
      state.shouldRefresh(
        for: restartedImport,
        at: start.addingTimeInterval(24 * 60 * 60)
      )
    )
    XCTAssertTrue(state.needsImportRefresh)
    XCTAssertTrue(state.needsFeedInRefresh)
    XCTAssertNil(
      state.totals(
        adjustedFor: restartedImport,
        at: start.addingTimeInterval(24 * 60 * 60)
      )
    )
  }

  private func snapshot(
    importCost: Double,
    earnings: Double,
    lastReset: Date
  ) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.4,
      batteryStateOfCharge: nil,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostCounterDollars: importCost,
      feedInEarningsCounterDollars: earnings,
      importCostCounterLastReset: lastReset,
      feedInEarningsCounterLastReset: lastReset
    )
  }

  private func totals(start: Date) -> HomeAssistantDailyEnergyTotals {
    HomeAssistantDailyEnergyTotals(
      importCostDollars: 0.20,
      feedInEarningsDollars: 0.91,
      interval: DateInterval(
        start: start,
        end: start.addingTimeInterval(24 * 60 * 60)
      )
    )
  }
}

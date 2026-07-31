import XCTest

@testable import Bruce

final class DailyEnergyRecorderLagRecoveryTests: XCTestCase {
  func testStaleRecorderRowAfterResetPreservesCarryUntilCatchUp() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let reset = Date(timeIntervalSince1970: 1)
    var (state, restarted) = makeStaleRecovery(
      start: start,
      reset: reset
    )
    try assertCarriedTotals(state, snapshot: restarted, start: start)

    let caughtUpLive = snapshot(
      importCost: 0.005,
      earnings: 0.006,
      lastReset: reset
    )
    XCTAssertFalse(
      state.shouldRefresh(
        for: caughtUpLive,
        at: start.addingTimeInterval(3)
      )
    )
    try assertLocallyAdvancedTotals(
      state,
      snapshot: caughtUpLive,
      start: start
    )

    let retry = start.addingTimeInterval(
      2 + HomeAssistantDailyEnergyRefreshState.failureRetryInterval
    )
    XCTAssertTrue(state.shouldRefresh(for: caughtUpLive, at: retry))
    state.noteSuccess(
      totals(
        importCost: 0.256,
        earnings: 0.937,
        start: start,
        counters: (0.006, 0.007),
        lastReset: reset
      ),
      snapshot: caughtUpLive,
      at: retry
    )

    XCTAssertFalse(state.needsImportRefresh)
    XCTAssertFalse(state.needsFeedInRefresh)
    XCTAssertFalse(state.isRecoveringImportReset)
    XCTAssertFalse(state.isRecoveringFeedInReset)
    try assertLocallyAdvancedTotals(
      state,
      snapshot: caughtUpLive,
      start: start
    )
  }

  private func makeStaleRecovery(
    start: Date,
    reset: Date
  ) -> (
    state: HomeAssistantDailyEnergyRefreshState,
    restarted: HomeAssistantHomeEnergySnapshot
  ) {
    let initial = snapshot(importCost: 2, earnings: 4, lastReset: reset)
    let beforeRestart = snapshot(
      importCost: 2.05,
      earnings: 4.02,
      lastReset: reset
    )
    let restarted = snapshot(importCost: 0, earnings: 0, lastReset: reset)
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(
      totals(
        importCost: 0.20,
        earnings: 0.91,
        start: start,
        counters: (2, 4),
        lastReset: reset
      ),
      snapshot: initial
    )
    XCTAssertFalse(
      state.shouldRefresh(
        for: beforeRestart,
        at: start.addingTimeInterval(1)
      )
    )
    XCTAssertTrue(
      state.shouldRefresh(for: restarted, at: start.addingTimeInterval(2))
    )

    state.noteSuccess(
      totals(
        importCost: 0.22,
        earnings: 0.92,
        start: start,
        counters: (2.02, 4.01),
        lastReset: reset
      ),
      snapshot: restarted,
      at: start.addingTimeInterval(2)
    )
    return (state, restarted)
  }

  private func assertCarriedTotals(
    _ state: HomeAssistantDailyEnergyRefreshState,
    snapshot: HomeAssistantHomeEnergySnapshot,
    start: Date
  ) throws {
    let carried = try XCTUnwrap(
      state.totals(
        adjustedFor: snapshot,
        at: start.addingTimeInterval(2)
      )
    )
    XCTAssertEqual(
      try XCTUnwrap(carried.importCostDollars),
      0.25,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      try XCTUnwrap(carried.feedInEarningsDollars),
      0.93,
      accuracy: 0.000_001
    )
    XCTAssertTrue(state.isRecoveringImportReset)
    XCTAssertTrue(state.isRecoveringFeedInReset)
    XCTAssertEqual(
      state.nextRefreshDate(after: start.addingTimeInterval(2)),
      start.addingTimeInterval(
        2 + HomeAssistantDailyEnergyRefreshState.failureRetryInterval
      )
    )
  }

  private func assertLocallyAdvancedTotals(
    _ state: HomeAssistantDailyEnergyRefreshState,
    snapshot: HomeAssistantHomeEnergySnapshot,
    start: Date
  ) throws {
    let totals = try XCTUnwrap(
      state.totals(
        adjustedFor: snapshot,
        at: start.addingTimeInterval(3)
      )
    )
    XCTAssertEqual(
      try XCTUnwrap(totals.importCostDollars),
      0.255,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      try XCTUnwrap(totals.feedInEarningsDollars),
      0.936,
      accuracy: 0.000_001
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

  private func totals(
    importCost: Double,
    earnings: Double,
    start: Date,
    counters: (importCost: Double, earnings: Double),
    lastReset: Date
  ) -> HomeAssistantDailyEnergyTotals {
    HomeAssistantDailyEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: earnings,
      interval: DateInterval(
        start: start,
        end: start.addingTimeInterval(24 * 60 * 60)
      ),
      importCounter: HomeAssistantEnergyCounterReference(
        value: counters.importCost,
        lastReset: lastReset
      ),
      feedInCounter: HomeAssistantEnergyCounterReference(
        value: counters.earnings,
        lastReset: lastReset
      )
    )
  }
}

extension DailyEnergyRecorderLagRecoveryTests {
  func testResetCheckpointDoesNotCrossDailyInterval() {
    let start = Date(timeIntervalSince1970: 1_000)
    let reset = Date(timeIntervalSince1970: 1)
    var (state, _) = makeStaleRecovery(start: start, reset: reset)
    let nextStart = start.addingTimeInterval(24 * 60 * 60)
    let live = snapshot(
      importCost: 0.005,
      earnings: 0.006,
      lastReset: reset
    )

    XCTAssertTrue(state.shouldRefresh(for: live, at: nextStart))
    state.noteSuccess(
      HomeAssistantDailyEnergyTotals(
        importCostDollars: nil,
        feedInEarningsDollars: 0.01,
        interval: DateInterval(
          start: nextStart,
          end: nextStart.addingTimeInterval(24 * 60 * 60)
        ),
        feedInCounter: HomeAssistantEnergyCounterReference(
          value: 0.006,
          lastReset: reset
        )
      ),
      snapshot: live,
      at: nextStart
    )

    let adjusted = state.totals(adjustedFor: live, at: nextStart)
    XCTAssertNil(adjusted?.importCostDollars)
    XCTAssertEqual(adjusted?.feedInEarningsDollars, 0.01)
    XCTAssertFalse(state.isRecoveringImportReset)
  }
}

import XCTest

@testable import Bruce

final class DailyEnergyResetRecoveryTests: XCTestCase {
  func testOlderStatisticResetMarkerAfterRestartKeepsRetrying() {
    let start = Date(timeIntervalSince1970: 1_000)
    let previousReset = Date(timeIntervalSince1970: 1)
    let currentReset = Date(timeIntervalSince1970: 2)
    let restartedSnapshot = snapshot(
      importCostCounter: 0,
      earningsCounter: 0,
      lastReset: currentReset
    )
    var state = HomeAssistantDailyEnergyRefreshState()

    state.noteSuccess(
      totals(
        importCost: 0.24,
        earnings: 0.98,
        start: start,
        importCounter: 2,
        earningsCounter: 4,
        statisticLastReset: previousReset
      ),
      snapshot: restartedSnapshot
    )

    XCTAssertFalse(
      state.shouldRefresh(
        for: restartedSnapshot,
        at: start.addingTimeInterval(1)
      )
    )
    let adjusted = state.totals(
      adjustedFor: restartedSnapshot,
      at: start.addingTimeInterval(1)
    )
    XCTAssertNil(adjusted?.importCostDollars)
    XCTAssertNil(adjusted?.feedInEarningsDollars)
    XCTAssertTrue(state.needsImportRefresh)
    XCTAssertTrue(state.needsFeedInRefresh)
  }

  func testZeroedCounterWithUnchangedResetMarkerRefreshesExactlyOnce() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let reset = Date(timeIntervalSince1970: 1)
    let initial = snapshot(
      importCostCounter: 2,
      earningsCounter: 4,
      lastReset: reset
    )
    let restarted = snapshot(
      importCostCounter: 0,
      earningsCounter: 0,
      lastReset: reset
    )
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(
      totals(importCost: 0.20, earnings: 0.91, start: start),
      snapshot: initial
    )

    XCTAssertTrue(
      state.shouldRefresh(for: restarted, at: start.addingTimeInterval(1))
    )
    state.noteSuccess(
      totals(
        importCost: 0.24,
        earnings: 0.98,
        start: start,
        importCounter: 0,
        earningsCounter: 0,
        statisticLastReset: reset
      ),
      snapshot: restarted
    )

    let adjusted = try XCTUnwrap(
      state.totals(
        adjustedFor: restarted,
        at: start.addingTimeInterval(1)
      )
    )
    XCTAssertFalse(
      state.shouldRefresh(for: restarted, at: start.addingTimeInterval(1))
    )
    XCTAssertEqual(adjusted.importCostDollars, 0.24)
    XCTAssertEqual(adjusted.feedInEarningsDollars, 0.98)
  }

  func testFailedResetRefreshSurvivesReconnectUntilSuccessfulRecovery() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let reset = Date(timeIntervalSince1970: 1)
    let initial = snapshot(
      importCostCounter: 2,
      earningsCounter: 4,
      lastReset: reset
    )
    let restarted = snapshot(
      importCostCounter: 0,
      earningsCounter: 0,
      lastReset: reset
    )
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(
      totals(importCost: 0.20, earnings: 0.91, start: start),
      snapshot: initial
    )
    XCTAssertTrue(
      state.shouldRefresh(for: restarted, at: start.addingTimeInterval(1))
    )
    state.noteFailure(at: start.addingTimeInterval(1))

    state.noteControlTransition()
    XCTAssertTrue(
      state.shouldRefresh(for: restarted, at: start.addingTimeInterval(2))
    )
    state.noteSuccess(
      totals(
        importCost: 0.24,
        earnings: 0.98,
        start: start,
        importCounter: 0,
        earningsCounter: 0,
        statisticLastReset: reset
      ),
      snapshot: restarted
    )

    let adjusted = try XCTUnwrap(
      state.totals(
        adjustedFor: restarted,
        at: start.addingTimeInterval(2)
      )
    )
    XCTAssertEqual(adjusted.importCostDollars, 0.24)
    XCTAssertEqual(adjusted.feedInEarningsDollars, 0.98)
  }

  func testRecorderCounterAheadOfLiveDoesNotLookLikeAnotherReset() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let reset = Date(timeIntervalSince1970: 1)
    let initial = snapshot(
      importCostCounter: 2,
      earningsCounter: 4,
      lastReset: reset
    )
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(
      totals(
        importCost: 0.20,
        earnings: 0.91,
        start: start,
        importCounter: 2.006,
        earningsCounter: 4.006,
        statisticLastReset: reset
      ),
      snapshot: initial
    )
    let caughtUp = snapshot(
      importCostCounter: 2.010,
      earningsCounter: 4.010,
      lastReset: reset
    )

    XCTAssertFalse(
      state.shouldRefresh(
        for: snapshot(
          importCostCounter: 2.003,
          earningsCounter: 4.003,
          lastReset: reset
        ),
        at: start.addingTimeInterval(1)
      )
    )
    XCTAssertFalse(
      state.shouldRefresh(for: caughtUp, at: start.addingTimeInterval(2))
    )
    let adjusted = try XCTUnwrap(
      state.totals(adjustedFor: caughtUp, at: start.addingTimeInterval(2))
    )
    XCTAssertEqual(try XCTUnwrap(adjusted.importCostDollars), 0.204, accuracy: 0.000_001)
    XCTAssertEqual(
      try XCTUnwrap(adjusted.feedInEarningsDollars),
      0.914,
      accuracy: 0.000_001
    )
  }

  private func snapshot(
    importCostCounter: Double?,
    earningsCounter: Double?,
    lastReset: Date?
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
      importCostCounterLastReset: lastReset,
      feedInEarningsCounterLastReset: lastReset
    )
  }

  private func totals(
    importCost: Double,
    earnings: Double,
    start: Date,
    importCounter: Double? = nil,
    earningsCounter: Double? = nil,
    statisticLastReset: Date? = nil
  ) -> HomeAssistantDailyEnergyTotals {
    HomeAssistantDailyEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: earnings,
      interval: DateInterval(
        start: start,
        end: start.addingTimeInterval(24 * 60 * 60)
      ),
      importCounter: importCounter.map {
        HomeAssistantEnergyCounterReference(
          value: $0,
          lastReset: statisticLastReset
        )
      },
      feedInCounter: earningsCounter.map {
        HomeAssistantEnergyCounterReference(
          value: $0,
          lastReset: statisticLastReset
        )
      }
    )
  }
}

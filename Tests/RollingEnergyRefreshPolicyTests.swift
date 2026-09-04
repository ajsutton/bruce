import XCTest

@testable import Bruce

final class RollingEnergyRefreshPolicyTests: XCTestCase {
  func testRollingTotalsRemainFrozenBetweenRecorderRefreshes() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    var state = HomeAssistantRollingEnergyRefreshState()
    state.noteSuccess(totals(at: start), at: start)

    let frozen = try XCTUnwrap(
      state.totals
    )

    XCTAssertEqual(frozen.importCostDollars, 0.20)
    XCTAssertEqual(frozen.feedInEarningsDollars, 0.91)
    XCTAssertFalse(state.shouldRefresh(at: start.addingTimeInterval(899)))
    XCTAssertTrue(state.shouldRefresh(at: start.addingTimeInterval(900)))
  }

  func testFailedStatisticsRefreshUsesNormalCadence() {
    let start = Date(timeIntervalSince1970: 1_000)
    var state = HomeAssistantRollingEnergyRefreshState()

    state.noteFailure(at: start)

    XCTAssertFalse(state.shouldRefresh(at: start.addingTimeInterval(899)))
    XCTAssertTrue(state.shouldRefresh(at: start.addingTimeInterval(900)))
  }

  func testPartialStatisticsKeepValidSiblingAndRetryMissingTotal() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    var state = HomeAssistantRollingEnergyRefreshState()
    state.noteSuccess(
      HomeAssistantRollingEnergyTotals(
        importCostDollars: 0.20,
        feedInEarningsDollars: nil,
        refreshAfter: start.addingTimeInterval(15 * 60)
      ),
      at: start
    )

    let frozen = try XCTUnwrap(
      state.totals
    )
    XCTAssertEqual(frozen.importCostDollars, 0.20)
    XCTAssertNil(frozen.feedInEarningsDollars)
    XCTAssertFalse(state.shouldRefresh(at: start.addingTimeInterval(899)))
    XCTAssertTrue(state.shouldRefresh(at: start.addingTimeInterval(900)))
  }

  func testControlTransitionRequiresFreshRecorderTotals() {
    let start = Date(timeIntervalSince1970: 1_000)
    var state = HomeAssistantRollingEnergyRefreshState()
    state.noteSuccess(totals(at: start), at: start)

    state.noteControlTransition()

    XCTAssertTrue(state.shouldRefresh(at: start.addingTimeInterval(1)))
  }

  func testOlderRecorderCutoffAfterReconnectRemainsLastKnown() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let newerCutoff = Date(timeIntervalSince1970: 950)
    var state = HomeAssistantRollingEnergyRefreshState()
    state.noteSuccess(
      totals(at: start, importCost: 0.20, importCapturedAt: newerCutoff),
      at: start
    )
    state.noteControlTransition()

    state.noteSuccess(
      totals(
        at: start.addingTimeInterval(1),
        importCost: 0.19,
        importCapturedAt: Date(timeIntervalSince1970: 900)
      ),
      at: start.addingTimeInterval(1)
    )

    let preserved = try XCTUnwrap(
      state.totals
    )
    XCTAssertEqual(preserved.importCostDollars, 0.20)
    XCTAssertEqual(preserved.importCapturedAt, newerCutoff)
    XCTAssertTrue(state.needsImportRefresh)
  }

  private func totals(
    at start: Date,
    importCost: Double = 0.20,
    importCapturedAt: Date? = nil
  ) -> HomeAssistantRollingEnergyTotals {
    HomeAssistantRollingEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: 0.91,
      refreshAfter: start.addingTimeInterval(15 * 60),
      importCapturedAt: importCapturedAt
    )
  }
}

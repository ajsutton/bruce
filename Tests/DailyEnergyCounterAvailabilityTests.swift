import XCTest

@testable import Bruce

final class DailyEnergyCounterAvailabilityTests: XCTestCase {
  func testMissingLiveCountersHidePreviouslyAuthoritativeTotals() {
    let start = Date(timeIntervalSince1970: 1_000)
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(
      totals(start: start),
      snapshot: snapshot(importCost: 2, earnings: 4)
    )

    let adjusted = state.totals(
      adjustedFor: snapshot(importCost: nil, earnings: nil),
      at: start.addingTimeInterval(1)
    )

    XCTAssertNil(adjusted?.importCostDollars)
    XCTAssertNil(adjusted?.feedInEarningsDollars)
  }

  func testCounterReturningAtZeroAfterAvailabilityGapRequiresRefresh() {
    let start = Date(timeIntervalSince1970: 1_000)
    var state = HomeAssistantDailyEnergyRefreshState()
    state.noteSuccess(
      totals(start: start),
      snapshot: snapshot(importCost: 2, earnings: 4)
    )

    XCTAssertFalse(
      state.shouldRefresh(
        for: snapshot(importCost: nil, earnings: nil),
        at: start.addingTimeInterval(1)
      )
    )
    XCTAssertTrue(
      state.shouldRefresh(
        for: snapshot(importCost: 0, earnings: 0),
        at: start.addingTimeInterval(2)
      )
    )
  }

  private func snapshot(
    importCost: Double?,
    earnings: Double?
  ) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.4,
      batteryStateOfCharge: nil,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostCounterDollars: importCost,
      feedInEarningsCounterDollars: earnings
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

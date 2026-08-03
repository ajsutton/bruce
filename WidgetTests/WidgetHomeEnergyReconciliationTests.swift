import XCTest

final class WidgetHomeEnergyReconciliationTests: XCTestCase {
  func testSnapshotRejectsInvalidRangesWithoutDiscardingOtherReadings() throws {
    let states = [
      try state("sensor.sigen_plant_pv_power", "-1"),
      try state("sensor.sigen_plant_battery_state_of_charge", "101"),
      try state("sensor.sigen_plant_consumed_power", "not-a-number"),
      try state("sensor.sigen_plant_grid_active_power", "1.2"),
    ]

    let snapshot = WidgetHomeEnergyClient.snapshot(
      from: states,
      totals: WidgetDailyEnergyTotals(
        importCostDollars: nil,
        feedInEarningsDollars: nil
      ),
      capturedAt: Date()
    )

    XCTAssertNil(snapshot.pvPowerKilowatts)
    XCTAssertNil(snapshot.batteryStateOfCharge)
    XCTAssertNil(snapshot.homeConsumptionKilowatts)
    XCTAssertEqual(snapshot.gridPowerKilowatts, 1.2)
  }

  func testRecorderLagIsAddedToDailyTotals() throws {
    let capturedAt = Date(timeIntervalSince1970: 10_000)
    let reset = Date(timeIntervalSince1970: 9_000)
    let states = [
      try state(
        "sensor.sigen_plant_total_imported_energy_cost",
        "10.5",
        lastReset: reset
      )
    ]
    let snapshot = WidgetHomeEnergyClient.snapshot(
      from: states,
      totals: WidgetDailyEnergyTotals(
        importCostDollars: 2,
        feedInEarningsDollars: nil,
        interval: DateInterval(start: reset, end: Date(timeIntervalSince1970: 11_000)),
        importCounter: WidgetEnergyCounterReference(value: 10, lastReset: reset)
      ),
      capturedAt: capturedAt
    )

    XCTAssertEqual(snapshot.importCostTodayDollars, 2.5)
  }

  func testResetMismatchPreservesPreviousTotalAsLastKnown() throws {
    let capturedAt = Date(timeIntervalSince1970: 10_000)
    let previousAt = Date(timeIntervalSince1970: 9_500)
    let statisticReset = Date(timeIntervalSince1970: 9_000)
    let liveReset = Date(timeIntervalSince1970: 9_800)
    let previous = HomeEnergyWidgetSnapshot(
      capturedAt: previousAt,
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostTodayDollars: 2.5,
      feedInEarningsTodayDollars: nil,
      dailyEnergyInterval: DateInterval(
        start: statisticReset,
        end: Date(timeIntervalSince1970: 11_000)
      )
    )
    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: [
          try state(
            "sensor.sigen_plant_total_imported_energy_cost",
            "0.2",
            lastReset: liveReset
          )
        ],
        currentTotals: WidgetDailyEnergyTotals(
          importCostDollars: 2,
          feedInEarningsDollars: nil,
          interval: DateInterval(
            start: statisticReset,
            end: Date(timeIntervalSince1970: 11_000)
          ),
          importCounter: WidgetEnergyCounterReference(value: 10, lastReset: statisticReset)
        ),
        previous: previous,
        capturedAt: capturedAt
      )
    )

    XCTAssertEqual(snapshot.importCostTodayDollars, 2.5)
    XCTAssertFalse(snapshot.importCostIsCurrent)
    XCTAssertEqual(snapshot.importCostCapturedAt, previousAt)
  }

  func testAuthoritativeRecorderDecreaseAppliesWhenStatesFail() throws {
    let capturedAt = Date(timeIntervalSince1970: 10_000)
    let interval = DateInterval(
      start: Date(timeIntervalSince1970: 9_000),
      end: Date(timeIntervalSince1970: 11_000)
    )
    let previous = HomeEnergyWidgetSnapshot(
      capturedAt: Date(timeIntervalSince1970: 9_500),
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostTodayDollars: 2.5,
      feedInEarningsTodayDollars: nil,
      dailyEnergyInterval: interval
    )
    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: nil,
        currentTotals: WidgetDailyEnergyTotals(
          importCostDollars: 2,
          feedInEarningsDollars: nil,
          interval: interval
        ),
        previous: previous,
        capturedAt: capturedAt
      )
    )

    XCTAssertEqual(snapshot.importCostTodayDollars, 2)
    XCTAssertTrue(snapshot.importCostIsCurrent)
    XCTAssertEqual(snapshot.importCostCapturedAt, capturedAt)
  }

  func testAuthoritativeRecorderDecreaseAppliesWhenLiveCounterIsMissing() throws {
    let capturedAt = Date(timeIntervalSince1970: 10_000)
    let interval = DateInterval(
      start: Date(timeIntervalSince1970: 9_000),
      end: Date(timeIntervalSince1970: 11_000)
    )
    let previous = HomeEnergyWidgetSnapshot(
      capturedAt: Date(timeIntervalSince1970: 9_500),
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostTodayDollars: 2.5,
      feedInEarningsTodayDollars: nil,
      dailyEnergyInterval: interval
    )
    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: [],
        currentTotals: WidgetDailyEnergyTotals(
          importCostDollars: 2,
          feedInEarningsDollars: nil,
          interval: interval
        ),
        previous: previous,
        capturedAt: capturedAt
      )
    )

    XCTAssertEqual(snapshot.importCostTodayDollars, 2)
    XCTAssertTrue(snapshot.importCostIsCurrent)
  }

  func testMissingSingleStatisticPreservesOnlyThatMetricAsStale() throws {
    let capturedAt = Date(timeIntervalSince1970: 10_000)
    let interval = DateInterval(
      start: Date(timeIntervalSince1970: 9_000),
      end: Date(timeIntervalSince1970: 11_000)
    )
    let previous = HomeEnergyWidgetSnapshot(
      capturedAt: Date(timeIntervalSince1970: 9_500),
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostTodayDollars: 2,
      feedInEarningsTodayDollars: 4,
      dailyEnergyInterval: interval
    )
    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: [],
        currentTotals: WidgetDailyEnergyTotals(
          importCostDollars: 2.5,
          feedInEarningsDollars: nil,
          interval: interval,
          importIsCurrent: true,
          feedInIsCurrent: false
        ),
        previous: previous,
        capturedAt: capturedAt
      )
    )

    XCTAssertEqual(snapshot.importCostTodayDollars, 2.5)
    XCTAssertTrue(snapshot.importCostIsCurrent)
    XCTAssertEqual(snapshot.feedInEarningsTodayDollars, 4)
    XCTAssertFalse(snapshot.feedInEarningsIsCurrent)
  }

  func testFailedDailyTotalsAreNotCarriedIntoANewDay() throws {
    let calendar = Calendar(identifier: .gregorian)
    let previousDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 23, minute: 59))
    )
    let capturedAt = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, minute: 1))
    )
    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: [try state("sensor.sigen_plant_battery_state_of_charge", "78")],
        currentTotals: nil,
        previous: HomeEnergyWidgetSnapshot(
          capturedAt: previousDate,
          pvPowerKilowatts: nil,
          batteryStateOfCharge: 50,
          homeConsumptionKilowatts: nil,
          gridPowerKilowatts: nil,
          generalPriceDollarsPerKilowattHour: nil,
          feedInPriceDollarsPerKilowattHour: nil,
          importCostTodayDollars: 2.43,
          feedInEarningsTodayDollars: 4.18,
          dailyEnergyInterval: Calendar(identifier: .gregorian).dateInterval(
            of: .day,
            for: previousDate
          )
        ),
        capturedAt: capturedAt
      )
    )

    XCTAssertNil(snapshot.importCostTodayDollars)
    XCTAssertNil(snapshot.feedInEarningsTodayDollars)
  }

  private func state(
    _ entityID: String,
    _ value: String,
    lastReset: Date? = nil
  ) throws -> WidgetHomeAssistantState {
    var object: [String: Any] = ["entity_id": entityID, "state": value]
    if let lastReset {
      object["attributes"] = ["last_reset": lastReset.formatted(.iso8601)]
    }
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(WidgetHomeAssistantState.self, from: data)
  }
}

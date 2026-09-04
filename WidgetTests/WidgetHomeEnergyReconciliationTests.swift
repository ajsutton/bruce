import XCTest

final class WidgetHomeEnergyReconciliationTests: XCTestCase {
  func testNewerRecorderCutoffReplacesAppValuePublishedLater() throws {
    let previous = HomeEnergyWidgetSnapshot(
      capturedAt: Date(timeIntervalSince1970: 10_000),
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostLast24HoursDollars: 2.5,
      feedInEarningsLast24HoursDollars: nil,
      importCostCapturedAt: Date(timeIntervalSince1970: 9_000)
    )

    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: nil,
        currentTotals: WidgetRollingEnergyTotals(
          importCostDollars: 2.6,
          feedInEarningsDollars: nil,
          importCapturedAt: Date(timeIntervalSince1970: 9_500)
        ),
        previous: previous,
        capturedAt: Date(timeIntervalSince1970: 10_100)
      )
    )

    XCTAssertEqual(snapshot.importCostLast24HoursDollars, 2.6)
    XCTAssertTrue(snapshot.importCostIsCurrent)
    XCTAssertEqual(snapshot.importCostCapturedAt, Date(timeIntervalSince1970: 9_500))
  }

  func testLegacyDailyCaptureDoesNotRejectFirstRollingTotal() throws {
    let current = HomeEnergyWidgetSnapshot(
      capturedAt: Date(timeIntervalSince1970: 10_000),
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostLast24HoursDollars: 2.5,
      feedInEarningsLast24HoursDollars: nil
    )
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any]
    )
    object["importCostTodayDollars"] = 2.5
    object.removeValue(forKey: "importCostLast24HoursDollars")
    let legacy = try JSONDecoder().decode(
      HomeEnergyWidgetSnapshot.self,
      from: JSONSerialization.data(withJSONObject: object)
    )

    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: nil,
        currentTotals: WidgetRollingEnergyTotals(
          importCostDollars: 2.6,
          feedInEarningsDollars: nil,
          importCapturedAt: Date(timeIntervalSince1970: 9_500)
        ),
        previous: legacy,
        capturedAt: Date(timeIntervalSince1970: 10_100)
      )
    )

    XCTAssertEqual(snapshot.importCostLast24HoursDollars, 2.6)
    XCTAssertTrue(snapshot.importCostIsCurrent)
  }
}

extension WidgetHomeEnergyReconciliationTests {
  func testSnapshotRejectsInvalidRangesWithoutDiscardingOtherReadings() throws {
    let states = [
      try state("sensor.sigen_plant_pv_power", "-1"),
      try state("sensor.sigen_plant_battery_state_of_charge", "101"),
      try state("sensor.sigen_plant_consumed_power", "not-a-number"),
      try state("sensor.sigen_plant_grid_active_power", "1.2"),
    ]

    let snapshot = WidgetHomeEnergyClient.snapshot(
      from: states,
      totals: WidgetRollingEnergyTotals(
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

  func testRecorderRollingWindowRemainsFrozenBetweenRefreshes() throws {
    let capturedAt = Date(timeIntervalSince1970: 10_000)
    let states = [
      try state(
        "sensor.sigen_plant_total_imported_energy_cost",
        "10.5"
      )
    ]
    let snapshot = WidgetHomeEnergyClient.snapshot(
      from: states,
      totals: WidgetRollingEnergyTotals(
        importCostDollars: 2,
        feedInEarningsDollars: nil
      ),
      capturedAt: capturedAt
    )

    XCTAssertEqual(snapshot.importCostLast24HoursDollars, 2)
  }

  func testOlderRecorderWindowPreservesNewerPreviousTotal() throws {
    let capturedAt = Date(timeIntervalSince1970: 10_000)
    let previousAt = Date(timeIntervalSince1970: 9_500)
    let statisticReset = Date(timeIntervalSince1970: 9_000)
    let previous = HomeEnergyWidgetSnapshot(
      capturedAt: previousAt,
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostLast24HoursDollars: 2.5,
      feedInEarningsLast24HoursDollars: nil
    )
    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: [
          try state(
            "sensor.sigen_plant_total_imported_energy_cost",
            "0.2"
          )
        ],
        currentTotals: WidgetRollingEnergyTotals(
          importCostDollars: 2,
          feedInEarningsDollars: nil,
          importCapturedAt: statisticReset
        ),
        previous: previous,
        capturedAt: capturedAt
      )
    )

    XCTAssertEqual(snapshot.importCostLast24HoursDollars, 2.5)
    XCTAssertFalse(snapshot.importCostIsCurrent)
    XCTAssertEqual(snapshot.importCostCapturedAt, previousAt)
  }

  func testAuthoritativeRecorderDecreaseAppliesWhenStatesFail() throws {
    let capturedAt = Date(timeIntervalSince1970: 10_000)
    let previous = HomeEnergyWidgetSnapshot(
      capturedAt: Date(timeIntervalSince1970: 9_500),
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostLast24HoursDollars: 2.5,
      feedInEarningsLast24HoursDollars: nil
    )
    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: nil,
        currentTotals: WidgetRollingEnergyTotals(
          importCostDollars: 2,
          feedInEarningsDollars: nil
        ),
        previous: previous,
        capturedAt: capturedAt
      )
    )

    XCTAssertEqual(snapshot.importCostLast24HoursDollars, 2)
    XCTAssertTrue(snapshot.importCostIsCurrent)
    XCTAssertEqual(snapshot.importCostCapturedAt, capturedAt)
  }

  func testAuthoritativeRecorderDecreaseAppliesWhenLiveCounterIsMissing() throws {
    let capturedAt = Date(timeIntervalSince1970: 10_000)
    let previous = HomeEnergyWidgetSnapshot(
      capturedAt: Date(timeIntervalSince1970: 9_500),
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostLast24HoursDollars: 2.5,
      feedInEarningsLast24HoursDollars: nil
    )
    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: [],
        currentTotals: WidgetRollingEnergyTotals(
          importCostDollars: 2,
          feedInEarningsDollars: nil
        ),
        previous: previous,
        capturedAt: capturedAt
      )
    )

    XCTAssertEqual(snapshot.importCostLast24HoursDollars, 2)
    XCTAssertTrue(snapshot.importCostIsCurrent)
  }

  func testMissingSingleStatisticPreservesOnlyThatMetricAsStale() throws {
    let capturedAt = Date(timeIntervalSince1970: 10_000)
    let previous = HomeEnergyWidgetSnapshot(
      capturedAt: Date(timeIntervalSince1970: 9_500),
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostLast24HoursDollars: 2,
      feedInEarningsLast24HoursDollars: 4
    )
    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: [],
        currentTotals: WidgetRollingEnergyTotals(
          importCostDollars: 2.5,
          feedInEarningsDollars: nil,
          importIsCurrent: true,
          feedInIsCurrent: false
        ),
        previous: previous,
        capturedAt: capturedAt
      )
    )

    XCTAssertEqual(snapshot.importCostLast24HoursDollars, 2.5)
    XCTAssertTrue(snapshot.importCostIsCurrent)
    XCTAssertEqual(snapshot.feedInEarningsLast24HoursDollars, 4)
    XCTAssertFalse(snapshot.feedInEarningsIsCurrent)
  }

  private func state(
    _ entityID: String,
    _ value: String
  ) throws -> WidgetHomeAssistantState {
    let object: [String: Any] = ["entity_id": entityID, "state": value]
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(WidgetHomeAssistantState.self, from: data)
  }
}

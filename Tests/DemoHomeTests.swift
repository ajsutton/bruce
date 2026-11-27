import XCTest

@testable import Bruce

@MainActor
final class DemoHomeTests: XCTestCase {
  func testClimateControlsPublishConfirmedStateToExistingObservers() async throws {
    let climate = DemoClimate()
    let updates = climate.temperatureUpdates()
    let confirmed = expectation(description: "Lounge target and power confirmed")
    let observation = Task {
      for try await update in updates {
        if case .live(let readings) = update,
          let lounge = readings.first(where: { $0.id == "climate.lounge" }),
          lounge.targetValue == 24, lounge.powerState == .off
        {
          confirmed.fulfill()
          return
        }
      }
    }
    defer {
      observation.cancel()
      updates.cancel()
    }
    try await climate.setTargetValue(24, entityID: "climate.lounge")
    try await climate.setPower(entityID: "climate.lounge", isOn: false)
    await fulfillment(of: [confirmed], timeout: 2)
  }

  func testGarageControlsPublishDoorLightAndLockChanges() async throws {
    let garage = DemoGarage()
    let updates = garage.garageDoorUpdates()
    let confirmed = expectation(description: "Garage controls confirmed")
    let observation = Task {
      for try await update in updates {
        if case .live(let doors) = update,
          let door = doors.first,
          door.doorState == .open, door.lightState == .illuminated, door.lockState == .locked
        {
          confirmed.fulfill()
          return
        }
      }
    }
    defer {
      observation.cancel()
      updates.cancel()
    }
    try await garage.sendGarageDoorCommand(.open, entityID: "cover.garage")
    try await garage.setGarageLight(entityID: "light.garage", isOn: true)
    try await garage.setGarageLock(entityID: "lock.garage", isLocked: true)
    await fulfillment(of: [confirmed], timeout: 2)
  }

  func testChargerModeUpdatesItsActivityAndSurvivesReload() async throws {
    let charger = DemoCharger()
    _ = try await charger.setEVChargingMode(.off)
    let stopped = try await charger.loadEVChargingSnapshot()
    XCTAssertEqual(stopped.mode, .off)
    XCTAssertEqual(stopped.activity, .switchedOff)
    _ = try await charger.setEVChargingMode(.charging)
    let charging = try await charger.loadEVChargingSnapshot()
    XCTAssertEqual(charging.mode, .charging)
    XCTAssertEqual(charging.activity, .charging(powerWatts: 3600))
  }

  func testUnknownDemoEntitiesFailInsteadOfChangingAnotherDevice() async {
    let climate = DemoClimate()
    do {
      try await climate.setPower(entityID: "climate.real_house", isOn: false)
      XCTFail("An unknown entity should be rejected")
    } catch {
      XCTAssertEqual(error as? DemoHomeError, .unknownEntity)
    }
  }

  func testDemoEnergyIncludesEveryHistorySeriesAndTariff() async throws {
    let energy = DemoEnergy(capturedAt: Date(timeIntervalSince1970: 1_800_000_000))
    let flow = try await energy.loadHomeEnergyFlowHistory()
    let battery = try await energy.loadHomeEnergyBatteryHistory()
    let prices = try await energy.loadHomeEnergyPriceHistory()
    XCTAssertTrue(flow.hasCompleteSeries)
    XCTAssertTrue(battery.hasReadings)
    XCTAssertTrue(prices.hasCompleteTariffs)
    XCTAssertEqual(flow.interval.end, energy.capturedAt)
    XCTAssertEqual(battery.interval, flow.interval)
    XCTAssertEqual(prices.interval, flow.interval)
    XCTAssertEqual(flow.interval.duration, 86400)
  }

  func testASecondDemoVisitStartsWithUnmodifiedState() async throws {
    let first = DemoGarage()
    try await first.sendGarageDoorCommand(.open, entityID: "cover.garage")
    let second = DemoGarage()
    let doors = try await second.loadGarageDoors()
    XCTAssertEqual(doors.first?.doorState, .closed)
  }

  func testCancelledDemoControlsDoNotMutateState() async throws {
    let garage = DemoGarage()
    let operation = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await garage.sendGarageDoorCommand(.open, entityID: "cover.garage")
    }
    do {
      try await operation.value
      XCTFail("A cancelled control should throw")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    let doors = try await garage.loadGarageDoors()
    XCTAssertEqual(doors.first?.doorState, .closed)
  }
}

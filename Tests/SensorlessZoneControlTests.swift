import Combine
import XCTest

@testable import Bruce

@MainActor
final class SensorlessZoneControlTests: XCTestCase {
  func testOpeningRemainsOptimisticUntilBothDamperAndZoneConfirm() async {
    let fixture = await loadedStore()
    fixture.store.setOpening(50, for: fixture.reading)
    await fulfillment(of: [fixture.controller.started(at: 0)], timeout: 1)
    XCTAssertEqual(fixture.store.readings.first?.opening?.value, 50)
    XCTAssertEqual(fixture.store.readings.first?.powerState, .poweredOn)
    XCTAssertTrue(fixture.store.isAdjusting(entityID: fixture.reading.id))
    let commands = await fixture.controller.commands
    XCTAssertEqual(commands, [.opening(entityID: "cover.kitchen_damper", value: 50)])
    fixture.controller.succeed(command: 0)
    let stale = kitchenReading(opening: 5, powerState: .off, name: "Kitchen renamed")
    await publish(stale, in: fixture)
    XCTAssertEqual(fixture.store.readings.first?.opening?.value, 50)
    XCTAssertTrue(fixture.store.isControlling(entityID: fixture.reading.id))
    await confirm(kitchenReading(opening: 50, powerState: .poweredOn), in: fixture)
    XCTAssertFalse(fixture.store.isControlling(entityID: fixture.reading.id))
    fixture.loader.finishRequest(0)
    await fixture.load.value
  }

  func testFailedOpeningRollsBackPercentageAndPower() async {
    let fixture = await loadedStore()
    fixture.store.setOpening(50, for: fixture.reading)
    await fulfillment(of: [fixture.controller.started(at: 0)], timeout: 1)
    let failed = expectation(description: "Opening failure reported")
    let subscription = fixture.store.$controlProblem.dropFirst().compactMap { $0 }.sink { _ in
      failed.fulfill()
    }
    fixture.controller.fail(command: 0)
    await fulfillment(of: [failed], timeout: 1)
    XCTAssertEqual(fixture.store.readings.first?.opening?.value, 5)
    XCTAssertEqual(fixture.store.readings.first?.powerState, .off)
    XCTAssertFalse(fixture.store.isControlling(entityID: fixture.reading.id))
    fixture.loader.finishRequest(0)
    await fixture.load.value
    withExtendedLifetime(subscription) {}
  }

  func testResetCancelsOpeningAndClearsValues() async {
    let fixture = await loadedStore(cancellableCommands: [0])
    fixture.store.setOpening(50, for: fixture.reading)
    await fulfillment(of: [fixture.controller.started(at: 0)], timeout: 1)
    fixture.store.reset()
    await fulfillment(of: [fixture.controller.cancelled(at: 0)], timeout: 1)
    XCTAssertTrue(fixture.store.readings.isEmpty)
    XCTAssertFalse(fixture.store.isControlling(entityID: fixture.reading.id))
    fixture.loader.finishRequest(0)
    await fixture.load.value
  }

  func testRepeatedOpeningChangesSendOnlyLatestQueuedPercentage() async {
    let fixture = await loadedStore(commandCount: 2)
    fixture.store.setOpening(25, for: fixture.reading)
    await fulfillment(of: [fixture.controller.started(at: 0)], timeout: 1)
    fixture.store.setOpening(50, for: fixture.reading)
    fixture.store.setOpening(75, for: fixture.reading)
    fixture.controller.succeed(command: 0)
    await fulfillment(of: [fixture.controller.started(at: 1)], timeout: 1)
    let commands = await fixture.controller.commands
    XCTAssertEqual(
      commands,
      [
        .opening(entityID: "cover.kitchen_damper", value: 25),
        .opening(entityID: "cover.kitchen_damper", value: 75),
      ])
    fixture.controller.succeed(command: 1)
    await confirm(kitchenReading(opening: 75, powerState: .poweredOn), in: fixture)
    XCTAssertEqual(fixture.store.readings.first?.opening?.value, 75)
    XCTAssertFalse(fixture.store.isControlling(entityID: fixture.reading.id))
    fixture.loader.finishRequest(0)
    await fixture.load.value
  }

  func testZeroOpeningConfirmsOffEvenWhenDamperRetainsMinimumPosition() async {
    let fixture = await loadedStore()
    fixture.store.setOpening(0, for: fixture.reading)
    await fulfillment(of: [fixture.controller.started(at: 0)], timeout: 1)
    let confirmed = expectation(description: "Off command confirmed")
    let cleared = fixture.store.$controllingEntityIDs.dropFirst().filter { $0.isEmpty }
    let subscription = cleared.sink { _ in
      confirmed.fulfill()
    }
    fixture.controller.succeed(command: 0)
    await fulfillment(of: [confirmed], timeout: 1)
    XCTAssertEqual(fixture.store.readings.first?.powerState, .off)
    XCTAssertEqual(fixture.store.readings.first?.opening?.value, 5)
    XCTAssertNil(fixture.store.controlProblem)
    fixture.loader.finishRequest(0)
    await fixture.load.value
    withExtendedLifetime(subscription) {}
  }

  func testTargetCallbackCannotReplaceAnInFlightOpeningAfterSensorStateChanges() async {
    let fixture = await loadedStore()
    fixture.store.setOpening(50, for: fixture.reading)
    await fulfillment(of: [fixture.controller.started(at: 0)], timeout: 1)
    let withSensor = HomeAssistantTemperatureReading(
      id: fixture.reading.id, name: "Kitchen", value: 22, targetValue: 25,
      unit: "°C", powerState: .off, kind: .zone, operatingMode: .off
    )
    await publish(withSensor, in: fixture)
    fixture.store.setTargetValue(24, for: withSensor)
    let failed = expectation(description: "Original opening ends")
    let subscription = fixture.store.$controlProblem.dropFirst().compactMap { $0 }.sink { _ in
      failed.fulfill()
    }
    fixture.controller.fail(command: 0)
    await fulfillment(of: [failed], timeout: 1)
    let commands = await fixture.controller.commands
    XCTAssertEqual(commands, [.opening(entityID: "cover.kitchen_damper", value: 50)])
    XCTAssertEqual(fixture.store.readings.first?.targetValue, 25)
    fixture.loader.finishRequest(0)
    await fixture.load.value
    withExtendedLifetime(subscription) {}
  }

  func testQueuedOpeningUsesLatestDamperAfterRegistryPairChanges() async {
    let fixture = await loadedStore(commandCount: 2)
    fixture.store.setOpening(25, for: fixture.reading)
    await fulfillment(of: [fixture.controller.started(at: 0)], timeout: 1)
    let renamed = kitchenReading(
      opening: 5, powerState: .off, name: "Kitchen renamed", damperID: "cover.new_kitchen_vent"
    )
    await publish(renamed, in: fixture)
    fixture.store.setOpening(75, for: renamed)
    fixture.controller.fail(command: 0)
    await fulfillment(of: [fixture.controller.started(at: 1)], timeout: 1)
    let commands = await fixture.controller.commands
    XCTAssertEqual(
      commands,
      [
        .opening(entityID: "cover.kitchen_damper", value: 25),
        .opening(entityID: "cover.new_kitchen_vent", value: 75),
      ])
    fixture.controller.succeed(command: 1)
    await confirm(
      kitchenReading(
        opening: 75, powerState: .poweredOn, name: "Kitchen renamed",
        damperID: "cover.new_kitchen_vent"), in: fixture)
    XCTAssertNil(fixture.store.controlProblem)
    XCTAssertEqual(fixture.store.readings.first?.opening?.entityID, "cover.new_kitchen_vent")
    fixture.loader.finishRequest(0)
    await fixture.load.value
  }

  private func kitchenReading(
    opening: Double, powerState: HomeAssistantTemperatureReading.PowerState,
    name: String = "Kitchen", damperID: String = "cover.kitchen_damper"
  ) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: "climate.kitchen", name: name, value: nil, targetValue: nil, unit: "°C",
      powerState: powerState, kind: .zone, operatingMode: powerState == .off ? .off : .fanOnly,
      opening: HomeAssistantZoneOpening(
        entityID: damperID, value: opening,
        isAvailable: true, supportsPosition: true)
    )
  }

  private func confirm(_ reading: HomeAssistantTemperatureReading, in fixture: OpeningFixture) async
  {
    let confirmed = expectation(description: "Opening confirmed by live state")
    let cleared = fixture.store.$controllingEntityIDs.dropFirst().filter { $0.isEmpty }
    let subscription = cleared.sink { _ in
      confirmed.fulfill()
    }
    fixture.loader.yieldRequest(0, update: .live([reading]))
    await fulfillment(of: [confirmed], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  private func loadedStore(commandCount: Int = 1, cancellableCommands: Set<Int> = []) async
    -> OpeningFixture
  {
    let reading = HomeAssistantTemperatureReading(
      id: "climate.kitchen", name: "Kitchen", value: nil, targetValue: nil, unit: "°C",
      powerState: .off, kind: .zone, operatingMode: .off,
      opening: HomeAssistantZoneOpening(
        entityID: "cover.kitchen_damper", value: 5,
        isAvailable: true, supportsPosition: true)
    )
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = OrderedClimateController(
      commandCount: commandCount, cancellableCommands: cancellableCommands)
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    let fixture = OpeningFixture(
      store: store, reading: reading, loader: loader, controller: controller, load: load)
    await publish(reading, in: fixture)
    return fixture
  }

  private func publish(_ reading: HomeAssistantTemperatureReading, in fixture: OpeningFixture) async
  {
    let live = expectation(description: "Live state received")
    let subscription = fixture.store.$readings.dropFirst().filter { $0.first?.name == reading.name }
      .sink { _ in
        live.fulfill()
      }
    fixture.loader.yieldRequest(0, update: .live([reading]))
    await fulfillment(of: [live], timeout: 1)
    withExtendedLifetime(subscription) {}
  }
}

@MainActor
private struct OpeningFixture {
  let store: HomeAssistantTemperatureStore
  let reading: HomeAssistantTemperatureReading
  let loader: ControlledTemperatureLoader
  let controller: OrderedClimateController
  let load: Task<Void, Never>
}

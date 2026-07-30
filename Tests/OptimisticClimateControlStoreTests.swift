import Combine
import XCTest

@testable import Bruce

@MainActor
final class OptimisticClimateControlStoreTests: XCTestCase {
  func testPowerCommandKeepsOptimisticStateUntilLiveStateConfirmsIt() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = BlockingClimateController()
    let fixture = await loadedStore(loader: loader, controller: controller)
    let store = fixture.store
    let reading = fixture.reading
    let load = fixture.load

    let command = Task {
      await store.setPower(for: reading, isOn: false)
    }
    await fulfillment(of: [controller.started], timeout: 1)

    XCTAssertTrue(store.isControlling(entityID: reading.id))
    XCTAssertTrue(store.isControllingClimateState(entityID: reading.id))
    XCTAssertFalse(store.isAdjustingTarget(entityID: reading.id))
    XCTAssertEqual(store.readings.first?.powerState, .off)
    controller.succeed()
    await command.value

    XCTAssertTrue(store.isControlling(entityID: reading.id))
    let refreshing = expectation(description: "Stale state refresh received")
    let refreshingSubscription = store.$isRefreshing.dropFirst().filter { $0 }.sink { _ in
      refreshing.fulfill()
    }
    loader.yieldRequest(0, update: .refreshing([reading]))
    await fulfillment(of: [refreshing], timeout: 1)
    let live = expectation(description: "Stale live state received")
    let liveSubscription = store.$isLive.dropFirst().filter { $0 }.sink { _ in
      live.fulfill()
    }
    loader.yieldRequest(0, update: .live([reading]))
    await fulfillment(of: [live], timeout: 1)
    XCTAssertEqual(store.readings.first?.powerState, .off)

    await confirm(
      reading.replacingClimateState(powerState: .off, operatingMode: .off),
      in: store,
      loader: loader
    )

    XCTAssertEqual(store.readings.first?.powerState, .off)
    let commands = await controller.commands
    XCTAssertEqual(commands, [.power(entityID: reading.id, isOn: false)])
    loader.finishRequest(0)
    await load.value
    withExtendedLifetime((refreshingSubscription, liveSubscription)) {}
  }

  func testModeCommandPublishesOptimisticStateUntilLiveStateConfirmsIt() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = BlockingClimateController()
    let fixture = await loadedStore(loader: loader, controller: controller)
    let store = fixture.store
    let reading = fixture.reading
    let load = fixture.load

    let command = Task {
      await store.setMode(.automatic, for: reading)
    }
    await fulfillment(of: [controller.started], timeout: 1)

    XCTAssertEqual(store.readings.first?.operatingMode, .automatic)
    controller.succeed()
    await command.value
    XCTAssertTrue(store.isControlling(entityID: reading.id))

    await confirm(
      reading.replacingClimateState(
        powerState: .poweredOn,
        operatingMode: .automatic
      ),
      in: store,
      loader: loader
    )

    XCTAssertEqual(store.readings.first?.operatingMode, .automatic)
    let commands = await controller.commands
    XCTAssertEqual(commands, [.mode(entityID: reading.id, mode: .automatic)])
    loader.finishRequest(0)
    await load.value
  }

  func testTargetCommandPublishesOptimisticValueUntilLiveStateConfirmsIt() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = BlockingClimateController()
    let fixture = await loadedStore(
      loader: loader,
      controller: controller,
      reading: controllableReading(kind: .zone)
    )
    let store = fixture.store
    let reading = fixture.reading
    let load = fixture.load

    store.setTargetValue(24.5, for: reading)
    await fulfillment(of: [controller.started], timeout: 1)

    XCTAssertEqual(store.readings.first?.targetValue, 24.5)
    XCTAssertTrue(store.isAdjustingTarget(entityID: reading.id))
    XCTAssertFalse(store.isControllingClimateState(entityID: reading.id))
    controller.succeed()

    await confirm(
      reading.replacingTargetValue(24.5),
      in: store,
      loader: loader
    )

    XCTAssertEqual(store.readings.first?.targetValue, 24.5)
    let commands = await controller.commands
    XCTAssertEqual(commands, [.targetValue(entityID: reading.id, value: 24.5)])
    loader.finishRequest(0)
    await load.value
  }

  func testPowerCommandIsIgnoredWhileTargetCommandIsPending() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = BlockingClimateController()
    let fixture = await loadedStore(
      loader: loader,
      controller: controller,
      reading: controllableReading(kind: .zone)
    )
    let store = fixture.store
    let reading = fixture.reading

    store.setTargetValue(24.5, for: reading)
    await fulfillment(of: [controller.started], timeout: 1)

    await store.setPower(for: reading, isOn: false)

    XCTAssertEqual(store.readings.first?.targetValue, 24.5)
    XCTAssertEqual(store.readings.first?.powerState, reading.powerState)
    let commands = await controller.commands
    XCTAssertEqual(
      commands,
      [.targetValue(entityID: reading.id, value: 24.5)]
    )

    controller.succeed()
    await confirm(
      reading.replacingTargetValue(24.5),
      in: store,
      loader: loader
    )
    loader.finishRequest(0)
    await fixture.load.value
  }

  func testAirConditionerTargetCannotBeChanged() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = RecordingClimateController()
    let fixture = await loadedStore(loader: loader, controller: controller)
    let store = fixture.store
    let reading = fixture.reading

    store.setTargetValue(24.5, for: reading)

    XCTAssertEqual(store.readings.first?.targetValue, reading.targetValue)
    XCTAssertFalse(store.isControlling(entityID: reading.id))
    let commands = await controller.commands
    XCTAssertTrue(commands.isEmpty)
    loader.finishRequest(0)
    await fixture.load.value
  }

  func testZoneTargetRejectsValuesOutsideAdvertisedRange() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = RecordingClimateController()
    let reading = controllableReading(
      kind: .zone,
      minimumTargetValue: 18,
      maximumTargetValue: 26
    )
    let fixture = await loadedStore(
      loader: loader,
      controller: controller,
      reading: reading
    )

    fixture.store.setTargetValue(17.5, for: reading)
    fixture.store.setTargetValue(26.5, for: reading)

    XCTAssertEqual(fixture.store.readings.first?.targetValue, reading.targetValue)
    XCTAssertFalse(fixture.store.isControlling(entityID: reading.id))
    let commands = await controller.commands
    XCTAssertTrue(commands.isEmpty)
    loader.finishRequest(0)
    await fixture.load.value
  }
}

extension OptimisticClimateControlStoreTests {
  func testConnectingInvalidatesPendingControlAndRejectsLateSuccess() async {
    await assertConnectionTransitionInvalidatesPendingControl(.connecting)
  }

  func testUnavailableInvalidatesPendingControlAndRejectsLateSuccess() async {
    await assertConnectionTransitionInvalidatesPendingControl(.unavailable)
  }

  private func assertConnectionTransitionInvalidatesPendingControl(
    _ connection: HomeAssistantConnectionState
  ) async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = BlockingClimateController()
    let fixture = await loadedStore(loader: loader, controller: controller)
    let command = Task {
      await fixture.store.setPower(for: fixture.reading, isOn: false)
    }
    await fulfillment(of: [controller.started], timeout: 1)
    XCTAssertEqual(fixture.store.readings.first?.powerState, .off)

    await fixture.store.synchronize(with: connection)
    XCTAssertEqual(
      fixture.store.readings.first?.powerState,
      fixture.reading.powerState
    )
    XCTAssertFalse(fixture.store.isControlling(entityID: fixture.reading.id))
    XCTAssertNil(fixture.store.controlProblem)

    controller.succeed()
    await command.value
    XCTAssertEqual(
      fixture.store.readings.first?.powerState,
      fixture.reading.powerState
    )
    XCTAssertNil(fixture.store.controlProblem)
    loader.finishRequest(0)
    await fixture.load.value
  }

  private func loadedStore(
    loader: ControlledTemperatureLoader,
    controller: any HomeAssistantClimateControlling,
    reading: HomeAssistantTemperatureReading? = nil,
    sleep: @escaping @Sendable (Duration) async throws -> Void = {
      try await Task.sleep(for: $0)
    }
  ) async -> LoadedControlStore {
    let store = HomeAssistantTemperatureStore(
      loader: loader,
      controller: controller,
      sleep: sleep
    )
    let reading = reading ?? controllableReading()
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    let live = expectation(description: "Live climate state published")
    let subscription = store.$isLive.dropFirst().sink { isLive in
      if isLive {
        live.fulfill()
      }
    }
    loader.yieldRequest(0, update: .live([reading]))
    await fulfillment(of: [live], timeout: 1)
    withExtendedLifetime(subscription) {}
    return LoadedControlStore(store: store, reading: reading, load: load)
  }

  private func confirm(
    _ reading: HomeAssistantTemperatureReading,
    in store: HomeAssistantTemperatureStore,
    loader: ControlledTemperatureLoader
  ) async {
    let confirmed = expectation(description: "Climate state confirmed")
    let subscription = store.$controllingEntityIDs.dropFirst().sink { entityIDs in
      if !entityIDs.contains(reading.id) {
        confirmed.fulfill()
      }
    }
    loader.yieldRequest(0, update: .live([reading]))
    await fulfillment(of: [confirmed], timeout: 1)
    XCTAssertFalse(store.isControlling(entityID: reading.id))
    withExtendedLifetime(subscription) {}
  }

  private func controllableReading(
    kind: HomeAssistantTemperatureReading.Kind = .airConditioner,
    minimumTargetValue: Double? = nil,
    maximumTargetValue: Double? = nil
  ) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: "climate.air_conditioner",
      name: "Air Conditioner",
      value: 22,
      targetValue: 23,
      unit: "°C",
      powerState: .poweredOn,
      kind: kind,
      operatingMode: .cooling,
      availableModes: [.automatic, .cooling],
      minimumTargetValue: minimumTargetValue,
      maximumTargetValue: maximumTargetValue
    )
  }
}

@MainActor
private struct LoadedControlStore {
  let store: HomeAssistantTemperatureStore
  let reading: HomeAssistantTemperatureReading
  let load: Task<Void, Never>
}

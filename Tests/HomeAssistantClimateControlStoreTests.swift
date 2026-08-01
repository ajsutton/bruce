import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantClimateControlStoreTests: XCTestCase {
  func testPresetTurnsOffNonMembersBeforeTurningOnMembers() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = OrderedClimateController(commandCount: 2)
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let upstairs = zoneReading(id: "climate.upstairs", powerState: .off)
    let downstairs = zoneReading(id: "climate.downstairs", powerState: .poweredOn)
    let spare = zoneReading(id: "climate.spare", powerState: .off)
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([upstairs, downstairs, spare]))
    await waitForLiveState(in: store)

    store.apply(
      HomeAssistantClimatePreset(
        id: .floor("upstairs"),
        name: "Upstairs",
        zoneEntityIDs: [upstairs.id]
      )
    )
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)

    let optimisticPowerStates = Dictionary(
      uniqueKeysWithValues: store.readings.map { ($0.id, $0.powerState) }
    )
    XCTAssertEqual(
      optimisticPowerStates,
      [upstairs.id: .poweredOn, downstairs.id: .off, spare.id: .off]
    )
    let firstCommands = await controller.commands
    XCTAssertEqual(firstCommands, [.power(entityID: downstairs.id, isOn: false)])
    controller.succeed(command: 0)
    await fulfillment(of: [controller.started(at: 1)], timeout: 1)
    let completedCommands = await controller.commands
    XCTAssertEqual(
      completedCommands,
      [
        .power(entityID: downstairs.id, isOn: false),
        .power(entityID: upstairs.id, isOn: true),
      ]
    )
    controller.succeed(command: 1)
    loader.finishRequest(0)
    await load.value
  }

  func testPresetFailureRollsBackAndDoesNotStartLaterCommands() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = OrderedClimateController(commandCount: 1)
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let upstairs = zoneReading(id: "climate.upstairs", powerState: .off)
    let downstairs = zoneReading(id: "climate.downstairs", powerState: .poweredOn)
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([upstairs, downstairs]))
    await waitForLiveState(in: store)
    let failed = expectation(description: "Preset failure published")
    let subscription = store.$controlProblem.compactMap { $0 }.prefix(1).sink { _ in
      failed.fulfill()
    }

    store.apply(
      HomeAssistantClimatePreset(
        id: .floor("upstairs"),
        name: "Upstairs",
        zoneEntityIDs: [upstairs.id]
      )
    )
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    controller.fail(command: 0)
    await fulfillment(of: [failed], timeout: 1)

    let commands = await controller.commands
    XCTAssertEqual(commands, [.power(entityID: downstairs.id, isOn: false)])
    XCTAssertEqual(store.readings, [upstairs, downstairs])
    withExtendedLifetime(subscription) {}
    loader.finishRequest(0)
    await load.value
  }

  func testResetCancelsAnActivePresetTransaction() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = OrderedClimateController(commandCount: 1, cancellableCommands: [0])
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let zone = zoneReading(id: "climate.zone", powerState: .poweredOn)
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([zone]))
    await waitForLiveState(in: store)

    store.apply(
      HomeAssistantClimatePreset(id: .none, name: "None", zoneEntityIDs: [])
    )
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)

    store.reset()

    await fulfillment(of: [controller.cancelled(at: 0)], timeout: 1)
    XCTAssertEqual(store.readings, [])
    loader.finishRequest(0)
    await load.value
  }

  func testClimateModeCommandRejectsModeNotAdvertisedByEntity() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = RecordingClimateController()
    let store = HomeAssistantTemperatureStore(
      loader: loader,
      controller: controller
    )
    let reading = controllableReading()
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([reading]))
    await waitForLiveState(in: store)

    await store.setMode(.heating, for: reading)

    let commands = await controller.commands
    XCTAssertEqual(commands, [])
    loader.finishRequest(0)
    await load.value
  }

  func testClimateControlFailureReportsProblemAndClearsPendingState() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = FailingClimateController()
    let store = HomeAssistantTemperatureStore(
      loader: loader,
      controller: controller
    )
    let reading = controllableReading()
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([reading]))
    await waitForLiveState(in: store)

    await store.setMode(.automatic, for: reading)

    XCTAssertFalse(store.isControlling(entityID: reading.id))
    XCTAssertEqual(store.readings, [reading])
    XCTAssertEqual(
      store.controlProblem,
      .init(name: "Air Conditioner")
    )
    loader.finishRequest(0)
    await load.value
  }

  func testCancelledClimateControlClearsPendingStateWithoutReportingProblem() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = CancellableClimateController()
    let store = HomeAssistantTemperatureStore(
      loader: loader,
      controller: controller
    )
    let reading = controllableReading()
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([reading]))
    await waitForLiveState(in: store)
    let command = Task {
      await store.setPower(for: reading, isOn: false)
    }
    await fulfillment(of: [controller.started], timeout: 1)

    command.cancel()
    await command.value

    XCTAssertFalse(store.isControlling(entityID: reading.id))
    XCTAssertNil(store.controlProblem)
    loader.finishRequest(0)
    await load.value
  }

  func testURLCancelledClimateControlDoesNotReportProblem() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let store = HomeAssistantTemperatureStore(
      loader: loader,
      controller: URLCancelledClimateController()
    )
    let reading = controllableReading()
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([reading]))
    await waitForLiveState(in: store)

    await store.setPower(for: reading, isOn: false)

    XCTAssertFalse(store.isControlling(entityID: reading.id))
    XCTAssertNil(store.controlProblem)
    loader.finishRequest(0)
    await load.value
  }

  func testAuthenticationFailureRequestsRecoveryAndClearsPendingState() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let recoveryRequested = expectation(description: "Authentication recovery requested")
    let store = HomeAssistantTemperatureStore(
      loader: loader,
      controller: AuthenticationFailingClimateController(),
      onAuthenticationRequired: {
        recoveryRequested.fulfill()
      }
    )
    let reading = controllableReading()
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([reading]))
    await waitForLiveState(in: store)

    await store.setMode(.cooling, for: reading)

    await fulfillment(of: [recoveryRequested], timeout: 1)
    XCTAssertFalse(store.isControlling(entityID: reading.id))
    XCTAssertEqual(
      store.controlProblem,
      .init(name: "Air Conditioner")
    )
    loader.finishRequest(0)
    await load.value
  }

}

extension HomeAssistantClimateControlStoreTests {
  fileprivate func controllableReading(
    id: String = "climate.air_conditioner",
    name: String = "Air Conditioner"
  ) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: id,
      name: name,
      value: 22,
      targetValue: 23,
      unit: "°C",
      powerState: .poweredOn,
      kind: .airConditioner,
      operatingMode: .cooling,
      availableModes: [.automatic, .cooling]
    )
  }

  fileprivate func zoneReading(
    id: String,
    powerState: HomeAssistantTemperatureReading.PowerState
  ) -> HomeAssistantTemperatureReading {
    let floorID = id.split(separator: ".").last.map(String.init)
    return HomeAssistantTemperatureReading(
      id: id,
      name: id,
      value: 22,
      targetValue: 23,
      unit: "°C",
      powerState: powerState,
      kind: .zone,
      operatingMode: powerState == .off ? .off : .cooling,
      floor: floorID.map {
        HomeAssistantClimateFloor(id: $0, name: $0.capitalized, level: nil)
      }
    )
  }

  fileprivate func waitForLiveState(in store: HomeAssistantTemperatureStore) async {
    if store.isLive {
      return
    }
    let live = expectation(description: "Live climate state published")
    let subscription = store.$isLive.dropFirst().sink { isLive in
      if isLive {
        live.fulfill()
      }
    }
    await fulfillment(of: [live], timeout: 1)
    withExtendedLifetime(subscription) {}
  }
}

import Combine
import XCTest

@testable import Bruce

@MainActor
final class RepeatedTargetControlStoreTests: XCTestCase {
  func testNewTargetReplacesPendingTargetWithoutDisablingAdjustments() async {
    let fixture = await loadedStore()
    let store = fixture.store
    let reading = fixture.reading

    store.setTargetValue(23.5, for: reading)
    store.setTargetValue(24, for: reading)
    store.setTargetValue(24.5, for: reading)
    await fulfillment(of: [fixture.controller.started(at: 0)], timeout: 1)

    XCTAssertEqual(store.readings.first?.targetValue, 24.5)
    let firstCommands = await fixture.controller.commands
    XCTAssertEqual(
      firstCommands,
      [.targetValue(entityID: reading.id, value: 23.5)]
    )

    fixture.controller.succeed(command: 0)
    await fulfillment(of: [fixture.controller.started(at: 1)], timeout: 1)
    let allCommands = await fixture.controller.commands
    XCTAssertEqual(
      allCommands,
      [
        .targetValue(entityID: reading.id, value: 23.5),
        .targetValue(entityID: reading.id, value: 24.5),
      ]
    )

    fixture.loader.yieldRequest(
      0,
      update: .live([reading.replacingTargetValue(24)])
    )
    XCTAssertEqual(store.readings.first?.targetValue, 24.5)
    XCTAssertTrue(store.isAdjustingTarget(entityID: reading.id))

    fixture.controller.succeed(command: 1)
    await confirm(fixture, targetValue: 24.5)

    fixture.loader.finishRequest(0)
    await fixture.load.value
  }

  func testFailureOfReplacedTargetStillSendsLatestTarget() async {
    let fixture = await loadedStore()
    let store = fixture.store
    let reading = fixture.reading

    store.setTargetValue(23.5, for: reading)
    await fulfillment(of: [fixture.controller.started(at: 0)], timeout: 1)
    store.setTargetValue(24, for: reading)

    fixture.controller.fail(command: 0)
    await fulfillment(of: [fixture.controller.started(at: 1)], timeout: 1)
    XCTAssertNil(store.controlProblem)
    XCTAssertEqual(store.readings.first?.targetValue, 24)

    fixture.controller.succeed(command: 1)
    await confirm(fixture, targetValue: 24)

    XCTAssertNil(store.controlProblem)
    fixture.loader.finishRequest(0)
    await fixture.load.value
  }

  func testImmediateResetPreventsTargetCommandFromStarting() async {
    let controller = OrderedClimateController(commandCount: 1)
    let fixture = await loadedStore(controller: controller)
    let store = fixture.store
    let reading = fixture.reading

    store.setTargetValue(23.5, for: reading)
    store.reset()
    await Task.yield()

    let commands = await controller.commands
    XCTAssertTrue(commands.isEmpty)
    fixture.loader.finishRequest(0)
    await fixture.load.value
  }

  func testLateOldTargetCompletionCannotHideNewTaskFromReset() async {
    let controller = OrderedClimateController(
      commandCount: 2,
      cancellableCommands: [1]
    )
    let fixture = await loadedStore(
      requestCount: 2,
      controller: controller
    )
    let store = fixture.store
    let reading = fixture.reading

    store.setTargetValue(23.5, for: reading)
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    store.reset()

    let reload = Task {
      await store.load()
    }
    await fulfillment(of: [fixture.loader.started(at: 1)], timeout: 1)
    await publishLive(reading, request: 1, in: fixture)
    store.setTargetValue(24, for: reading)
    await fulfillment(of: [controller.started(at: 1)], timeout: 1)

    controller.succeed(command: 0)
    await Task.yield()
    store.reset()
    await fulfillment(of: [controller.cancelled(at: 1)], timeout: 1)

    let commands = await controller.commands
    XCTAssertEqual(
      commands,
      [
        .targetValue(entityID: reading.id, value: 23.5),
        .targetValue(entityID: reading.id, value: 24),
      ]
    )
    XCTAssertNil(store.controlProblem)
    fixture.loader.finishRequest(0)
    fixture.loader.finishRequest(1)
    await fixture.load.value
    await reload.value
  }

  private func loadedStore(
    requestCount: Int = 1,
    controller: OrderedClimateController = OrderedClimateController(commandCount: 2)
  ) async -> RepeatedTargetControlFixture {
    let loader = ControlledTemperatureLoader(requestCount: requestCount)
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let reading = HomeAssistantTemperatureReading(
      id: "climate.living_room",
      name: "Living Room",
      value: 22,
      targetValue: 23,
      unit: "°C",
      powerState: .poweredOn,
      kind: .zone,
      operatingMode: .cooling,
      availableModes: [.automatic, .cooling]
    )
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
    return RepeatedTargetControlFixture(
      store: store,
      reading: reading,
      loader: loader,
      controller: controller,
      load: load
    )
  }

  private func publishLive(
    _ reading: HomeAssistantTemperatureReading,
    request: Int,
    in fixture: RepeatedTargetControlFixture
  ) async {
    let live = expectation(description: "Reconnected climate state published")
    let subscription = fixture.store.$isLive.dropFirst().sink { isLive in
      if isLive {
        live.fulfill()
      }
    }
    fixture.loader.yieldRequest(request, update: .live([reading]))
    await fulfillment(of: [live], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  private func confirm(
    _ fixture: RepeatedTargetControlFixture,
    targetValue: Double
  ) async {
    let confirmed = expectation(description: "Latest target confirmed")
    let subscription = fixture.store.$controllingEntityIDs.dropFirst().sink { entityIDs in
      if !entityIDs.contains(fixture.reading.id) {
        confirmed.fulfill()
      }
    }
    fixture.loader.yieldRequest(
      0,
      update: .live([fixture.reading.replacingTargetValue(targetValue)])
    )
    await fulfillment(of: [confirmed], timeout: 1)
    XCTAssertFalse(fixture.store.isControlling(entityID: fixture.reading.id))
    withExtendedLifetime(subscription) {}
  }
}

@MainActor
private struct RepeatedTargetControlFixture {
  let store: HomeAssistantTemperatureStore
  let reading: HomeAssistantTemperatureReading
  let loader: ControlledTemperatureLoader
  let controller: OrderedClimateController
  let load: Task<Void, Never>
}

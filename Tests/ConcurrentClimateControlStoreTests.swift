import Combine
import XCTest

@testable import Bruce

@MainActor
final class ConcurrentClimateControlStoreTests: XCTestCase {
  func testOlderCommandCannotReplaceNewerControlProblem() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = OrderedClimateController(commandCount: 2)
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let firstReading = controllableReading(id: "climate.first", name: "First")
    let secondReading = controllableReading(id: "climate.second", name: "Second")
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([firstReading, secondReading]))
    await waitForLiveState(in: store)
    let firstCommand = Task {
      await store.setPower(for: firstReading, isOn: false)
    }
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    let secondCommand = Task {
      await store.setPower(for: secondReading, isOn: false)
    }
    await fulfillment(of: [controller.started(at: 1)], timeout: 1)

    controller.fail(command: 1)
    await secondCommand.value
    controller.fail(command: 0)
    await firstCommand.value

    XCTAssertEqual(
      store.controlProblem,
      .init(message: "Bruce couldn’t update Second.")
    )
    loader.finishRequest(0)
    await load.value
  }

  func testOlderFailureIsReportedAfterNewerCommandSucceeds() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = OrderedClimateController(commandCount: 2)
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let firstReading = controllableReading(id: "climate.first", name: "First")
    let secondReading = controllableReading(id: "climate.second", name: "Second")
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([firstReading, secondReading]))
    await waitForLiveState(in: store)
    let firstCommand = Task {
      await store.setPower(for: firstReading, isOn: false)
    }
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    let secondCommand = Task {
      await store.setPower(for: secondReading, isOn: false)
    }
    await fulfillment(of: [controller.started(at: 1)], timeout: 1)

    controller.succeed(command: 1)
    await secondCommand.value
    controller.fail(command: 0)
    await firstCommand.value

    XCTAssertEqual(
      store.controlProblem,
      .init(message: "Bruce couldn’t update First.")
    )
    loader.finishRequest(0)
    await load.value
  }

  func testResetInvalidatesPendingClimateControlFailure() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = OrderedClimateController(commandCount: 1)
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
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
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)

    store.reset()
    controller.fail(command: 0)
    await command.value

    XCTAssertTrue(store.readings.isEmpty)
    XCTAssertFalse(store.isControlling(entityID: reading.id))
    XCTAssertNil(store.controlProblem)
    loader.finishRequest(0)
    await load.value
  }

  private func controllableReading(
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

  private func waitForLiveState(in store: HomeAssistantTemperatureStore) async {
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

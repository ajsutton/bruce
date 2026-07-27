import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantClimateControlStoreTests: XCTestCase {
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
      .init(message: "Bruce couldn’t update Air Conditioner.")
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
      .init(message: "Bruce couldn’t update Air Conditioner.")
    )
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

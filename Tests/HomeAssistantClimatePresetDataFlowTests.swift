import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantClimatePresetDataFlowTests: XCTestCase {
  func testPresetRejectsMembershipCapturedBeforeZonesChanged() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = RecordingClimateController()
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let upstairs = zoneReading(id: "climate.upstairs", powerState: .off)
    let downstairs = zoneReading(id: "climate.downstairs", powerState: .off)
    let spare = zoneReading(id: "climate.spare", powerState: .off)
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([upstairs, downstairs]))
    await waitForLiveState(in: store)
    guard
      let stalePreset = HomeAssistantTemperatureSummary(readings: store.readings)
        .climatePresets.first(where: { $0.id == .all })
    else {
      XCTFail("Expected an All preset.")
      return
    }
    let zonesChanged = expectation(description: "Climate zones changed")
    let subscription = store.$readings.dropFirst().prefix(1).sink { _ in
      zonesChanged.fulfill()
    }
    loader.yieldRequest(0, update: .live([upstairs, downstairs, spare]))
    await fulfillment(of: [zonesChanged], timeout: 1)

    store.apply(stalePreset)
    await Task.yield()

    let commands = await controller.commands
    XCTAssertEqual(commands, [])
    XCTAssertEqual(store.readings, [upstairs, downstairs, spare])
    withExtendedLifetime(subscription) {}
    loader.finishRequest(0)
    await load.value
  }

  func testPresetRollsBackWhenHomeAssistantReportsUnavailable() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = OrderedClimateController(commandCount: 1, cancellableCommands: [0])
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let upstairs = zoneReading(id: "climate.upstairs", powerState: .off)
    let downstairs = zoneReading(id: "climate.downstairs", powerState: .poweredOn)
    let unavailableDownstairs = zoneReading(
      id: "climate.downstairs",
      powerState: .unavailable
    )
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([upstairs, downstairs]))
    await waitForLiveState(in: store)
    let failed = expectation(description: "Unavailable preset failure published")
    let subscription = store.$controlProblem.compactMap { $0 }.prefix(1).sink { _ in
      failed.fulfill()
    }

    store.apply(upstairsPreset(upstairs))
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([upstairs, unavailableDownstairs]))

    await fulfillment(of: [failed, controller.cancelled(at: 0)], timeout: 1)
    XCTAssertEqual(store.readings, [upstairs, unavailableDownstairs])
    withExtendedLifetime(subscription) {}
    loader.finishRequest(0)
    await load.value
  }

  func testPresetBlocksManualControlOfAnUnchangedZone() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = OrderedClimateController(commandCount: 1, cancellableCommands: [0])
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let upstairs = zoneReading(id: "climate.upstairs", powerState: .off)
    let downstairs = zoneReading(id: "climate.downstairs", powerState: .poweredOn)
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([upstairs, downstairs]))
    await waitForLiveState(in: store)

    store.apply(
      HomeAssistantClimatePreset(
        id: .all,
        name: "All",
        zoneEntityIDs: [upstairs.id, downstairs.id]
      )
    )
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)

    await store.setPower(for: downstairs, isOn: false)

    let commands = await controller.commands
    XCTAssertEqual(commands, [.power(entityID: upstairs.id, isOn: true)])
    store.reset()
    await fulfillment(of: [controller.cancelled(at: 0)], timeout: 1)
    loader.finishRequest(0)
    await load.value
  }

  func testPresetTimeoutRollsBackAllZonesAndCancelsRemainingWork() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = OrderedClimateController(commandCount: 2, cancellableCommands: [1])
    let sleeper = PresetConfirmationSleeper()
    let store = HomeAssistantTemperatureStore(
      loader: loader,
      controller: controller,
      sleep: sleeper.sleep
    )
    let upstairs = zoneReading(id: "climate.upstairs", powerState: .off)
    let downstairs = zoneReading(id: "climate.downstairs", powerState: .poweredOn)
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([upstairs, downstairs]))
    await waitForLiveState(in: store)
    let failed = expectation(description: "Preset timeout published")
    let subscription = store.$controlProblem.compactMap { $0 }.prefix(1).sink { _ in
      failed.fulfill()
    }

    store.apply(upstairsPreset(upstairs))
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    controller.succeed(command: 0)
    await fulfillment(
      of: [sleeper.started, controller.started(at: 1)],
      timeout: 1
    )

    sleeper.finish()

    await fulfillment(of: [failed, controller.cancelled(at: 1)], timeout: 1)
    XCTAssertEqual(store.readings, [upstairs, downstairs])
    withExtendedLifetime(subscription) {}
    loader.finishRequest(0)
    await load.value
  }

  private func upstairsPreset(
    _ upstairs: HomeAssistantTemperatureReading
  ) -> HomeAssistantClimatePreset {
    HomeAssistantClimatePreset(
      id: .floor("upstairs"),
      name: "Upstairs",
      zoneEntityIDs: [upstairs.id]
    )
  }

  private func zoneReading(
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

  private func waitForLiveState(in store: HomeAssistantTemperatureStore) async {
    if store.isLive { return }
    let live = expectation(description: "Live climate state published")
    let subscription = store.$isLive.dropFirst().sink { isLive in
      if isLive { live.fulfill() }
    }
    await fulfillment(of: [live], timeout: 1)
    withExtendedLifetime(subscription) {}
  }
}

private final class PresetConfirmationSleeper: @unchecked Sendable {
  let started = XCTestExpectation(description: "Preset confirmation timeout started")

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, any Error>?

  func sleep(for duration: Duration) async throws {
    try await withCheckedThrowingContinuation { continuation in
      lock.withLock { self.continuation = continuation }
      started.fulfill()
    }
  }

  func finish() {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume()
  }
}

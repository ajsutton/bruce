import Combine
import XCTest

@testable import Bruce

@MainActor
final class ClimatePresetTransactionTests: XCTestCase {
  func testUnavailableUnchangedZoneCancelsPreset() async {
    let controller = OrderedClimateController(commandCount: 1, cancellableCommands: [0])
    let setup = await setup(
      controller: controller,
      readings: [zone("upstairs", .off), zone("downstairs", .poweredOn)]
    )
    setup.store.apply(allPreset(setup.store.readings))
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)

    setup.loader.yieldRequest(
      0,
      update: .live([zone("upstairs", .off), zone("downstairs", .unavailable)])
    )

    await fulfillment(of: [controller.cancelled(at: 0)], timeout: 1)
    await waitForPowerState(.unavailable, entityID: "climate.downstairs", in: setup.store)
    XCTAssertTrue(setup.store.canControl(setup.store.readings[0]))
    await finish(setup)
  }

  func testUnavailableConfirmedZoneCancelsRemainingPresetCommand() async {
    let controller = OrderedClimateController(commandCount: 2, cancellableCommands: [1])
    let setup = await setup(
      controller: controller,
      readings: [zone("upstairs", .off), zone("downstairs", .poweredOn)]
    )
    setup.store.apply(upstairsPreset())
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    controller.succeed(command: 0)
    await fulfillment(of: [controller.started(at: 1)], timeout: 1)
    setup.loader.yieldRequest(
      0,
      update: .live([zone("upstairs", .off), zone("downstairs", .off)])
    )
    await Task.yield()

    setup.loader.yieldRequest(
      0,
      update: .live([zone("upstairs", .off), zone("downstairs", .unavailable)])
    )

    await fulfillment(of: [controller.cancelled(at: 1)], timeout: 1)
    await waitForPowerState(.unavailable, entityID: "climate.downstairs", in: setup.store)
    await finish(setup)
  }

  func testMembershipChangeCancelsPreset() async {
    let controller = OrderedClimateController(commandCount: 1, cancellableCommands: [0])
    let bedroomLabel = HomeAssistantClimatePresetLabel(id: "bedrooms", name: "Bedrooms")
    let setup = await setup(
      controller: controller,
      readings: [
        zone("bedroom", .off, labels: [bedroomLabel]),
        zone("living", .poweredOn),
      ]
    )
    setup.store.apply(
      HomeAssistantClimatePreset(
        id: .label("bedrooms"),
        name: "Bedrooms",
        zoneEntityIDs: ["climate.bedroom"]
      )
    )
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)

    setup.loader.yieldRequest(
      0,
      update: .live([zone("bedroom", .off), zone("living", .poweredOn)])
    )

    await fulfillment(of: [controller.cancelled(at: 0)], timeout: 1)
    XCTAssertNotNil(setup.store.controlProblem)
    await finish(setup)
  }

  func testLateOldCompletionCannotAffectReplacementPreset() async {
    let controller = OrderedClimateController(commandCount: 2, cancellableCommands: [1])
    let setup = await setup(
      controller: controller,
      readings: [zone("upstairs", .off), zone("downstairs", .poweredOn)]
    )
    setup.store.apply(upstairsPreset())
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    setup.loader.yieldRequest(
      0,
      update: .live([zone("upstairs", .off), zone("downstairs", .unavailable)])
    )
    await waitForPowerState(.unavailable, entityID: "climate.downstairs", in: setup.store)
    setup.loader.yieldRequest(
      0,
      update: .live([zone("upstairs", .off), zone("downstairs", .poweredOn)])
    )
    await waitForPowerState(.poweredOn, entityID: "climate.downstairs", in: setup.store)

    setup.store.apply(allPreset(setup.store.readings))
    await fulfillment(of: [controller.started(at: 1)], timeout: 1)
    controller.succeed(command: 0)
    await Task.yield()

    XCTAssertEqual(
      setup.store.readings.first(where: { $0.id == "climate.upstairs" })?.powerState,
      .poweredOn
    )
    XCTAssertTrue(setup.store.isControlling(entityID: "climate.upstairs"))
    controller.succeed(command: 1)
    setup.loader.yieldRequest(
      0,
      update: .live([zone("upstairs", .poweredOn), zone("downstairs", .poweredOn)])
    )
    await waitForPowerState(.poweredOn, entityID: "climate.upstairs", in: setup.store)
    await finish(setup)
  }
}

extension ClimatePresetTransactionTests {
  private func setup(
    controller: any HomeAssistantClimateControlling,
    readings: [HomeAssistantTemperatureReading]
  ) async -> ClimatePresetTestSetup {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live(readings))
    await waitForLiveState(in: store)
    return ClimatePresetTestSetup(store: store, loader: loader, load: load)
  }

  private func finish(_ setup: ClimatePresetTestSetup) async {
    setup.loader.finishRequest(0)
    await setup.load.value
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

  private func waitForPowerState(
    _ powerState: HomeAssistantTemperatureReading.PowerState,
    entityID: String,
    in store: HomeAssistantTemperatureStore
  ) async {
    if store.readings.first(where: { $0.id == entityID })?.powerState == powerState {
      return
    }
    let changed = expectation(description: "Climate power state changed")
    let subscription = store.$readings.dropFirst().sink { readings in
      if readings.first(where: { $0.id == entityID })?.powerState == powerState {
        changed.fulfill()
      }
    }
    await fulfillment(of: [changed], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  private func zone(
    _ name: String,
    _ powerState: HomeAssistantTemperatureReading.PowerState,
    labels: [HomeAssistantClimatePresetLabel] = []
  ) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: "climate.\(name)",
      name: name.capitalized,
      value: 22,
      targetValue: 23,
      unit: "°C",
      powerState: powerState,
      kind: .zone,
      operatingMode: powerState == .off ? .off : .cooling,
      floor: HomeAssistantClimateFloor(id: name, name: name.capitalized, level: nil),
      presetLabels: labels
    )
  }

  private func upstairsPreset() -> HomeAssistantClimatePreset {
    HomeAssistantClimatePreset(
      id: .floor("upstairs"),
      name: "Upstairs",
      zoneEntityIDs: ["climate.upstairs"]
    )
  }

  private func allPreset(
    _ readings: [HomeAssistantTemperatureReading]
  ) -> HomeAssistantClimatePreset {
    HomeAssistantClimatePreset(
      id: .all,
      name: "All",
      zoneEntityIDs: Set(readings.filter { $0.kind == .zone }.map(\.id))
    )
  }
}

private struct ClimatePresetTestSetup {
  let store: HomeAssistantTemperatureStore
  let loader: ControlledTemperatureLoader
  let load: Task<Void, Never>
}

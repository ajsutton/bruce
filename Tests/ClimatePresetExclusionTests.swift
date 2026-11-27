import Combine
import XCTest

@testable import Bruce

final class ClimatePresetExclusionTests: XCTestCase {
  func testExactHomeAssistantLabelIsRecognizedRegardlessOfCapitalization() throws {
    for name in ["Climate Preset: Exclude", "Climate preset: exclude"] {
      let metadata = HomeAssistantRegistryClient.climateMetadata(
        entities: [
          HomeAssistantRegistryEntity(
            id: "climate.kitchen", platform: "airtouch5", uniqueID: "zone_6",
            deviceID: nil, areaID: nil, icon: nil, originalIcon: nil, labelIDs: ["exclude"]
          )
        ], devices: [], areas: [],
        labels: [HomeAssistantRegistryLabel(id: "exclude", name: name)]
      )
      let readings = try HomeAssistantAPIClient.temperatures(
        from: Data(
          """
          [{"entity_id":"climate.kitchen","state":"off","attributes":{
            "friendly_name":"Kitchen","current_temperature":22,"temperature":24}}]
          """.utf8),
        unit: "°C", climateMetadata: metadata
      )
      XCTAssertTrue(try XCTUnwrap(readings.first).isExcludedFromClimatePresets, name)
    }
  }

  func testExcludedZoneIsAbsentFromAllFloorAndLabelPresets() {
    let summary = HomeAssistantTemperatureSummary(readings: [kitchen(), lounge()])

    XCTAssertEqual(
      summary.climatePresets.map(\.id), [.all, .label("shared"), .floor("ground"), .none])
    for preset in summary.climatePresets where preset.id != .none {
      XCTAssertEqual(preset.zoneEntityIDs, ["climate.lounge"])
    }
    XCTAssertEqual(summary.selectedClimatePresetID, HomeAssistantClimatePreset.Identifier.none)
    XCTAssertEqual(summary.rooms.count, 2)
  }

  func testOnlyNoneIsOfferedWhenEveryZoneIsExcluded() {
    let summary = HomeAssistantTemperatureSummary(readings: [kitchen()])
    XCTAssertEqual(summary.climatePresets.map(\.id), [.none])
  }

  @MainActor
  func testAllTurnsOnOtherZonesWithoutTurningOnKitchen() async throws {
    let controller = OrderedClimateController(commandCount: 1)
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let readings = [kitchen(), lounge()]
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live(readings))
    await waitForLiveState(in: store)

    let preset = try XCTUnwrap(
      HomeAssistantTemperatureSummary(readings: readings).climatePresets.first)
    store.apply(preset)
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    let commands = await controller.commands
    XCTAssertEqual(commands, [.power(entityID: "climate.lounge", isOn: true)])
    controller.succeed(command: 0)
    store.reset()
    loader.finishRequest(0)
    await load.value
  }

  @MainActor
  func testPresetTurnsOffManuallyEnabledExcludedKitchenBeforeTurningOnMembers() async throws {
    let controller = OrderedClimateController(commandCount: 2)
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let readings = [
      kitchen().replacingClimateState(powerState: .poweredOn, operatingMode: .fanOnly), lounge(),
    ]
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live(readings))
    await waitForLiveState(in: store)

    let preset = try XCTUnwrap(
      HomeAssistantTemperatureSummary(readings: readings).climatePresets.first)
    store.apply(preset)
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    let firstCommands = await controller.commands
    XCTAssertEqual(firstCommands, [.power(entityID: "climate.kitchen", isOn: false)])
    controller.succeed(command: 0)
    await fulfillment(of: [controller.started(at: 1)], timeout: 1)
    let commands = await controller.commands
    XCTAssertEqual(
      commands,
      [
        .power(entityID: "climate.kitchen", isOn: false),
        .power(entityID: "climate.lounge", isOn: true),
      ])
    controller.succeed(command: 1)
    store.reset()
    loader.finishRequest(0)
    await load.value
  }

  @MainActor
  func testExcludedKitchenCanStillBeTurnedOnManually() async throws {
    let controller = RecordingClimateController()
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let store = HomeAssistantTemperatureStore(loader: loader, controller: controller)
    let reading = kitchen()
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.yieldRequest(0, update: .live([reading]))
    await waitForLiveState(in: store)

    XCTAssertTrue(store.canControl(reading))
    await store.setPower(for: reading, isOn: true)
    let commands = await controller.commands
    XCTAssertEqual(commands, [.power(entityID: "climate.kitchen", isOn: true)])
    store.reset()
    loader.finishRequest(0)
    await load.value
  }

  @MainActor
  private func waitForLiveState(in store: HomeAssistantTemperatureStore) async {
    if store.isLive { return }
    let live = expectation(description: "Live climate state published")
    let subscription = store.$isLive.dropFirst().filter { $0 }.sink { _ in live.fulfill() }
    await fulfillment(of: [live], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  private func kitchen() -> HomeAssistantTemperatureReading {
    zone(id: "climate.kitchen", labels: [.init(id: "exclude", name: "Exclude")])
  }

  private func lounge() -> HomeAssistantTemperatureReading {
    zone(id: "climate.lounge", labels: [])
  }

  private func zone(
    id: String, labels: [HomeAssistantClimatePresetLabel]
  ) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: id, name: id, value: 22, targetValue: 24, unit: "°C", powerState: .off,
      kind: .zone, operatingMode: .off,
      floor: .init(id: "ground", name: "Ground floor", level: 0),
      presetLabels: labels + [.init(id: "shared", name: "Shared")]
    )
  }
}

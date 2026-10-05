import XCTest

@testable import Bruce

final class SensorlessZoneTests: XCTestCase {
  func testKitchenAppearsWithOpeningInsteadOfReportedTargetTemperature() throws {
    let readings = try HomeAssistantAPIClient.temperatures(
      from: kitchenStates, unit: "°C", climateMetadata: kitchenMetadata
    )
    let kitchen = try XCTUnwrap(readings.first)
    XCTAssertEqual(readings.count, 1)
    XCTAssertEqual(kitchen.name, "Kitchen")
    XCTAssertEqual(kitchen.kind, .zone)
    XCTAssertNil(kitchen.value)
    XCTAssertNil(kitchen.targetValue)
    XCTAssertEqual(kitchen.powerState, .off)
    XCTAssertEqual(kitchen.opening?.entityID, "cover.renamed_kitchen_vent")
    XCTAssertEqual(kitchen.opening?.value, 5)
    XCTAssertTrue(kitchen.opening?.canSetValue(50) == true)
    XCTAssertFalse(kitchen.canSetTargetValue(25))
    XCTAssertEqual(
      HomeAssistantTemperatureSummary(readings: readings).climatePresets.first?.zoneEntityIDs,
      ["climate.kitchen"])
    XCTAssertNil(HomeAssistantTemperatureSummary(readings: readings).averageRoomTemperature)
  }

  func testSensorlessZoneDoesNotChangeAverageOfMeasuredRooms() throws {
    let kitchen = try XCTUnwrap(
      HomeAssistantAPIClient.temperatures(
        from: kitchenStates, unit: "°C", climateMetadata: kitchenMetadata
      ).first)
    let lounge = HomeAssistantTemperatureReading(
      id: "climate.lounge", name: "Lounge", value: 22, targetValue: 24,
      unit: "°C", powerState: .poweredOn, kind: .zone
    )
    XCTAssertEqual(
      HomeAssistantTemperatureSummary(readings: [kitchen, lounge]).averageRoomTemperature, 22)
  }

  func testTemperatureControlledZonesDoNotExposeManualDamperControl() throws {
    let data = Data(
      try XCTUnwrap(String(data: kitchenStates, encoding: .utf8))
        .replacingOccurrences(
          of: "\"current_temperature\": null", with: "\"current_temperature\": 22"
        ).utf8)
    let kitchen = try XCTUnwrap(
      HomeAssistantAPIClient.temperatures(
        from: data, unit: "°C", climateMetadata: kitchenMetadata
      ).first)
    XCTAssertEqual(kitchen.value, 22)
    XCTAssertEqual(kitchen.targetValue, 25)
    XCTAssertNil(kitchen.opening)
  }

  func testUnavailableDamperDisablesOpeningWhileZoneRemainsVisible() throws {
    let data = Data(
      try XCTUnwrap(String(data: kitchenStates, encoding: .utf8))
        .replacingOccurrences(of: "\"state\": \"open\"", with: "\"state\": \"unavailable\"").utf8)
    let kitchen = try XCTUnwrap(
      HomeAssistantAPIClient.temperatures(
        from: data, unit: "°C", climateMetadata: kitchenMetadata
      ).first)
    XCTAssertEqual(kitchen.powerState, .off)
    XCTAssertFalse(kitchen.opening?.canSetValue(50) == true)
  }

  func testRegistryLinksDamperByAirTouchZoneIdentityRatherThanEntityName() {
    let entities = [
      registryEntity(id: "climate.kitchen", uniqueID: "zone_6", deviceID: "kitchen"),
      registryEntity(id: "cover.wrong", uniqueID: "zone_6_open_percentage", deviceID: "other"),
      registryEntity(
        id: "cover.renamed_kitchen_vent", uniqueID: "zone_6_open_percentage", deviceID: "kitchen"),
    ]
    let metadata = HomeAssistantRegistryClient.climateMetadata(
      entities: entities, devices: [], areas: [])
    XCTAssertEqual(metadata["climate.kitchen"]?.damperEntityID, "cover.renamed_kitchen_vent")
    XCTAssertEqual(Set(metadata.keys), ["climate.kitchen"])
  }

  func testOpeningUpdatesInvalidateCardPresentation() throws {
    let kitchen = try XCTUnwrap(
      HomeAssistantAPIClient.temperatures(
        from: kitchenStates, unit: "°C", climateMetadata: kitchenMetadata
      ).first)
    let opening = try XCTUnwrap(kitchen.opening)
    XCTAssertFalse(
      HomeAssistantTemperaturePresentation.matches(
        [kitchen], [kitchen.replacingOpening(opening.replacingValue(50))]
      ))
  }

  func testOpeningRejectsInvalidPercentages() {
    let opening = HomeAssistantZoneOpening(
      entityID: "cover.kitchen", value: 50,
      isAvailable: true, supportsPosition: true)
    for value in [-1, 101, Double.nan, Double.infinity, 25.5] {
      XCTAssertFalse(opening.canSetValue(value))
    }
  }

  private func registryEntity(id: String, uniqueID: String, deviceID: String)
    -> HomeAssistantRegistryEntity
  {
    HomeAssistantRegistryEntity(
      id: id, platform: "airtouch5", uniqueID: uniqueID,
      deviceID: deviceID, areaID: nil, icon: nil, originalIcon: nil)
  }
}

private let kitchenMetadata = [
  "climate.kitchen": HomeAssistantClimateMetadata(
    icon: nil, kind: .zone, damperEntityID: "cover.renamed_kitchen_vent"
  )
]

private let kitchenStates = Data(
  #"""
  [
    {"entity_id": "climate.kitchen", "state": "off", "attributes": {
      "friendly_name": "Kitchen", "current_temperature": null, "temperature": 25,
      "hvac_modes": ["off", "fan_only"], "supported_features": 401
    }},
    {"entity_id": "cover.renamed_kitchen_vent", "state": "open", "attributes": {
      "current_position": 5, "device_class": "damper", "supported_features": 7
    }}
  ]
  """#.utf8)

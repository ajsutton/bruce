import XCTest

@testable import Bruce

final class HomeAssistantTemperatureDecodingTests: XCTestCase {
  func testTemperatureLoadingUsesEntityNameWhenFriendlyNameIsMissing() throws {
    let temperatures = try decodeTemperature(
      state: "cool",
      attributes: #""current_temperature": 27.5, "temperature": 24"#
    )

    XCTAssertEqual(temperatures.first?.name, "Upstairs Air Conditioner")
  }

  func testTemperatureLoadingMapsOffState() throws {
    let temperatures = try decodeTemperature(
      state: "off",
      attributes: #""current_temperature": 27.5, "temperature": 24"#
    )

    XCTAssertEqual(temperatures.first?.powerState, .off)
    XCTAssertEqual(temperatures.first?.operatingMode, .off)
  }

  func testTemperatureLoadingMapsAirConditionerModes() throws {
    let states: [(String, HomeAssistantTemperatureReading.OperatingMode)] = [
      ("auto", .automatic),
      ("cool", .cooling),
      ("dry", .drying),
      ("fan_only", .fanOnly),
      ("heat", .heating),
    ]

    for (state, expectedMode) in states {
      let temperatures = try decodeTemperature(
        state: state,
        attributes: #""current_temperature": 27.5, "temperature": 24"#
      )

      XCTAssertEqual(temperatures.first?.operatingMode, expectedMode)
    }
  }

  func testTemperatureLoadingIncludesAdvertisedControllableModes() throws {
    let temperatures = try decodeTemperature(
      state: "cool",
      attributes: """
        "current_temperature": 27.5,
        "temperature": 24,
        "hvac_modes": ["off", "heat", "cool", "auto", "dry", "fan_only", "unknown"]
        """
    )

    XCTAssertEqual(
      temperatures.first?.availableModes,
      [.heating, .cooling, .automatic, .drying, .fanOnly]
    )
  }

  func testTemperatureLoadingUsesNoModesWhenCapabilitiesAreMissing() throws {
    let temperatures = try decodeTemperature(
      state: "cool",
      attributes: #""current_temperature": 27.5, "temperature": 24"#
    )

    XCTAssertEqual(temperatures.first?.availableModes, [])
  }

  func testTemperatureLoadingUsesNormalizedRegistryKind() throws {
    let data = temperatureData(
      state: "cool",
      attributes: #""current_temperature": 27.5, "temperature": 24"#
    )
    let metadata = HomeAssistantClimateMetadata(icon: nil, kind: .airConditioner)

    let temperatures = try HomeAssistantAPIClient.temperatures(
      from: data,
      unit: "°C",
      climateMetadata: ["climate.upstairs_air_conditioner": metadata]
    )

    XCTAssertEqual(temperatures.first?.kind, .airConditioner)
  }

  func testTemperatureLoadingAllowsMissingTarget() throws {
    let temperatures = try decodeTemperature(
      state: "cool",
      attributes: #""current_temperature": 27.5"#
    )

    XCTAssertNil(temperatures.first?.targetValue)
  }

  func testTemperatureLoadingIncludesTargetAdjustmentRangeAndStep() throws {
    let temperatures = try decodeTemperature(
      state: "cool",
      attributes: """
        "current_temperature": 27.5,
        "temperature": 24,
        "min_temp": 16,
        "max_temp": 30,
        "target_temp_step": 0.5
        """
    )

    XCTAssertEqual(temperatures.first?.minimumTargetValue, 16)
    XCTAssertEqual(temperatures.first?.maximumTargetValue, 30)
    XCTAssertEqual(temperatures.first?.targetValueStep, 0.5)
  }

  func testTemperatureLoadingUsesPrecisionWhenTargetStepIsMissing() throws {
    let temperatures = try decodeTemperature(
      state: "cool",
      attributes: """
        "current_temperature": 27.5,
        "temperature": 24,
        "precision": 1
        """
    )

    XCTAssertEqual(temperatures.first?.targetValueStep, 1)
  }

  func testTargetDisplayPrecisionFollowsAdvertisedStep() throws {
    let temperatures = try decodeTemperature(
      state: "cool",
      attributes: """
        "current_temperature": 27.5,
        "temperature": 22.25,
        "target_temp_step": 0.25
        """
    )

    XCTAssertEqual(temperatures.first?.targetValueFractionLength, 2)
  }

  func testTemperatureLoadingUsesConfiguredTemperatureUnit() throws {
    let data = Data(
      #"""
      {
        "unit_system": {
          "temperature": "°F"
        }
      }
      """#.utf8
    )

    XCTAssertEqual(try HomeAssistantAPIClient.temperatureUnit(from: data), "°F")
  }

  func testTemperatureLoadingRejectsMalformedStatePayload() {
    XCTAssertThrowsError(
      try HomeAssistantAPIClient.temperatures(from: Data("{}".utf8), unit: "°C")
    ) { error in
      guard case HomeAssistantAPIError.invalidResponse = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  private func decodeTemperature(
    state: String,
    attributes: String
  ) throws -> [HomeAssistantTemperatureReading] {
    try HomeAssistantAPIClient.temperatures(
      from: temperatureData(state: state, attributes: attributes),
      unit: "°C"
    )
  }

  private func temperatureData(state: String, attributes: String) -> Data {
    Data(
      """
      [{
        "entity_id": "climate.upstairs_air_conditioner",
        "state": "\(state)",
        "attributes": {
          \(attributes)
        }
      }]
      """.utf8
    )
  }
}

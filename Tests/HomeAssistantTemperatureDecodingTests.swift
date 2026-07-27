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
  }

  func testTemperatureLoadingAllowsMissingTarget() throws {
    let temperatures = try decodeTemperature(
      state: "cool",
      attributes: #""current_temperature": 27.5"#
    )

    XCTAssertNil(temperatures.first?.targetValue)
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
    let data = Data(
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

    return try HomeAssistantAPIClient.temperatures(from: data, unit: "°C")
  }
}

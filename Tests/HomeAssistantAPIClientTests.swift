import XCTest

@testable import Bruce

final class HomeAssistantAPIClientTests: XCTestCase {
  func testConnectionCheckAcceptsHomeAssistantStatus() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data(#"{"message":"API running."}"#.utf8), statusCode: 200)]
    )
    try await session.install(fixture.credentials())
    let client = HomeAssistantAPIClient(session: session)

    let status = try await client.checkConnection()

    XCTAssertEqual(status, HomeAssistantAPIStatus(message: "API running."))
  }

  func testConnectionCheckRejectsAnIncompatiblePayload() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data("{}".utf8), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(session: session).checkConnection()
      XCTFail("Expected an incompatible server response.")
    } catch HomeAssistantAPIError.incompatibleServer {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testConnectionCheckRejectsAnArbitraryMessage() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data(#"{"message":"not Home Assistant"}"#.utf8), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(session: session).checkConnection()
      XCTFail("Expected an incompatible server response.")
    } catch HomeAssistantAPIError.incompatibleServer {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testTemperatureLoadingReturnsOnlyAvailableTemperatureSensors() throws {
    let temperatures = try HomeAssistantAPIClient.temperatures(from: temperatureStatesData)

    XCTAssertEqual(
      temperatures,
      [
        HomeAssistantTemperatureReading(
          id: "sensor.bedroom_temperature",
          name: "Bedroom",
          value: 21,
          unit: "°C",
          updatedAt: try Date.ISO8601FormatStyle().parse("2026-07-27T01:01:00Z")
        ),
        HomeAssistantTemperatureReading(
          id: "sensor.outdoor_temperature",
          name: "Outdoor",
          value: 18.25,
          unit: "°C",
          updatedAt: try Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            .parse("2026-07-27T01:02:03.456Z")
        ),
      ]
    )
  }

  func testTemperatureLoadingUsesEntityNameWhenFriendlyNameIsMissing() throws {
    let data = Data(
      #"""
      [{
        "entity_id": "sensor.pool_water_temperature",
        "state": "27.5",
        "attributes": {
          "device_class": "temperature",
          "unit_of_measurement": "°C"
        }
      }]
      """#.utf8
    )

    let temperatures = try HomeAssistantAPIClient.temperatures(from: data)

    XCTAssertEqual(temperatures.first?.name, "Pool Water Temperature")
  }

  func testTemperatureLoadingRejectsMalformedStatePayload() {
    XCTAssertThrowsError(
      try HomeAssistantAPIClient.temperatures(from: Data("{}".utf8))
    ) { error in
      guard case HomeAssistantAPIError.invalidResponse = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  private var temperatureStatesData: Data {
    Data(
      #"""
      [
        {
          "entity_id": "sensor.outdoor_temperature",
          "state": "18.25",
          "attributes": {
            "device_class": "temperature",
            "friendly_name": "Outdoor",
            "unit_of_measurement": "°C"
          },
          "last_updated": "2026-07-27T01:02:03.456Z"
        },
        {
          "entity_id": "sensor.bedroom_temperature",
          "state": "21",
          "attributes": {
            "device_class": "temperature",
            "friendly_name": "Bedroom",
            "unit_of_measurement": "°C"
          },
          "last_updated": "2026-07-27T01:01:00Z"
        },
        {
          "entity_id": "sensor.unavailable_temperature",
          "state": "unavailable",
          "attributes": {
            "device_class": "temperature",
            "friendly_name": "Unavailable"
          }
        },
        {
          "entity_id": "sensor.humidity",
          "state": "52",
          "attributes": {
            "device_class": "humidity",
            "friendly_name": "Humidity"
          }
        }
      ]
      """#.utf8
    )
  }
}

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

  func testTemperatureLoadingUsesHomeAssistantConfigurationUnit() async throws {
    let fixture = SessionFixture()
    let configurationData = Data(
      #"{"unit_system":{"temperature":"°F"}}"#.utf8
    )
    let session = fixture.makeSession(
      apiResponses: [
        .success(configurationData, statusCode: 200),
        .success(temperatureStatesData, statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())

    let temperatures = try await HomeAssistantAPIClient(session: session).loadTemperatures()

    XCTAssertEqual(temperatures.map(\.unit), ["°F", "°F"])
    XCTAssertEqual(
      fixture.apiLoader.requests.compactMap { $0.url?.path },
      ["/api/config", "/api/states"]
    )
  }

  func testCancelledTemperatureLoadDoesNotRequestStatesAfterConfiguration() async throws {
    let fixture = SessionFixture()
    let loader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let now = fixture.now
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { now }
      ),
      loader: loader,
      now: { now }
    )
    try await session.install(fixture.credentials())
    let load = Task {
      try await HomeAssistantAPIClient(session: session).loadTemperatures()
    }
    await fulfillment(of: [loader.started], timeout: 1)

    load.cancel()
    loader.succeed(
      with: Data(#"{"unit_system":{"temperature":"°C"}}"#.utf8),
      statusCode: 200
    )

    do {
      _ = try await load.value
      XCTFail("Expected the temperature load to be cancelled.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(
      loader.requests.compactMap { $0.url?.path },
      ["/api/config"]
    )
  }

  func testTemperatureLoadingReturnsOnlyClimateCurrentTemperatures() throws {
    let temperatures = try HomeAssistantAPIClient.temperatures(
      from: temperatureStatesData,
      unit: "°C"
    )

    XCTAssertEqual(
      temperatures,
      [
        HomeAssistantTemperatureReading(
          id: "climate.bedroom",
          name: "Bedroom Air Conditioner",
          value: 21,
          unit: "°C",
          updatedAt: try Date.ISO8601FormatStyle().parse("2026-07-27T01:01:00Z")
        ),
        HomeAssistantTemperatureReading(
          id: "climate.living_room",
          name: "Living Room",
          value: 23.5,
          unit: "°C",
          updatedAt: try Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            .parse("2026-07-27T01:02:03.456Z"),
          icon: "mdi:sofa"
        ),
      ]
    )
  }

  func testTemperatureLoadingUsesEntityNameWhenFriendlyNameIsMissing() throws {
    let data = Data(
      #"""
      [{
        "entity_id": "climate.upstairs_air_conditioner",
        "state": "cool",
        "attributes": {
          "current_temperature": 27.5
        }
      }]
      """#.utf8
    )

    let temperatures = try HomeAssistantAPIClient.temperatures(from: data, unit: "°C")

    XCTAssertEqual(temperatures.first?.name, "Upstairs Air Conditioner")
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

  private var temperatureStatesData: Data {
    Data(
      #"""
      [
        {
          "entity_id": "climate.living_room",
          "state": "cool",
          "attributes": {
            "current_temperature": 23.5,
            "friendly_name": "Living Room",
            "icon": "mdi:sofa"
          },
          "last_updated": "2026-07-27T01:02:03.456Z"
        },
        {
          "entity_id": "climate.bedroom",
          "state": "heat",
          "attributes": {
            "current_temperature": 21,
            "friendly_name": "Bedroom Air Conditioner"
          },
          "last_updated": "2026-07-27T01:01:00Z"
        },
        {
          "entity_id": "climate.unavailable",
          "state": "off",
          "attributes": {
            "current_temperature": null,
            "friendly_name": "Unavailable"
          }
        },
        {
          "entity_id": "weather.home",
          "state": "sunny",
          "attributes": {
            "temperature": 30,
            "forecast": [
              {"temperature": 31},
              {"temperature": 29}
            ],
            "friendly_name": "Home Forecast"
          }
        },
        {
          "entity_id": "sensor.outdoor_temperature",
          "state": "18.25",
          "attributes": {
            "device_class": "temperature",
            "friendly_name": "Outdoor",
            "unit_of_measurement": "°C"
          }
        }
      ]
      """#.utf8
    )
  }
}

import XCTest

@testable import Bruce

final class HomeAssistantAPIClientTests: XCTestCase {
  func testStatesRejectMalformedOrderingTimestamp() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(
          Data(
            #"""
            [{
              "entity_id": "climate.bedroom",
              "state": "cool",
              "attributes": {},
              "last_updated": "not-a-timestamp"
            }]
            """#.utf8
          ),
          statusCode: 200
        )
      ]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(session: session).loadHomeAssistantStates()
      XCTFail("Expected malformed ordering timestamp to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Unexpected state decoding error: \(error)")
    }
  }
}

extension HomeAssistantAPIClientTests {
  func testConnectionCheckAcceptsHomeAssistantStatus() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: Array(
        repeating: .success(Data(#"{"message":"API running."}"#.utf8), statusCode: 200),
        count: 2
      )
    )
    try await session.install(fixture.credentials())
    let client = HomeAssistantAPIClient(session: session)

    let status = try await client.checkConnection()

    XCTAssertEqual(status, HomeAssistantAPIStatus(message: "API running."))
  }

  func testConnectionCheckRejectsAnIncompatiblePayload() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: Array(repeating: .success(Data("{}".utf8), statusCode: 200), count: 2)
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
      apiResponses: Array(
        repeating: .success(
          Data(#"{"message":"not Home Assistant"}"#.utf8),
          statusCode: 200
        ),
        count: 2
      )
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

    let temperatures = try await HomeAssistantAPIClient(
      session: session,
      climateMetadataLoader: StubClimateMetadataLoader()
    ).loadTemperatures()

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
          targetValue: 22,
          unit: "°C",
          powerState: .poweredOn,
          operatingMode: .heating
        ),
        HomeAssistantTemperatureReading(
          id: "climate.living_room",
          name: "Living Room",
          value: 23.5,
          targetValue: 24,
          unit: "°C",
          powerState: .poweredOn,
          operatingMode: .cooling,
          icon: "mdi:sofa"
        ),
      ]
    )
  }

  func testTemperatureLoadingUsesRegistryIconWithoutReplacingStateIcon() throws {
    let temperatures = try HomeAssistantAPIClient.temperatures(
      from: temperatureStatesData,
      unit: "°C",
      climateMetadata: [
        "climate.bedroom": HomeAssistantClimateMetadata(icon: "mdi:bed", kind: .other),
        "climate.living_room": HomeAssistantClimateMetadata(
          icon: "mdi:office-building",
          kind: .other
        ),
      ]
    )

    XCTAssertEqual(temperatures.first(where: { $0.id == "climate.bedroom" })?.icon, "mdi:bed")
    XCTAssertEqual(
      temperatures.first(where: { $0.id == "climate.living_room" })?.icon,
      "mdi:sofa"
    )
  }

  func testTemperatureLoadingContinuesWhenClimateMetadataIsUnavailable() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(Data(#"{"unit_system":{"temperature":"°C"}}"#.utf8), statusCode: 200),
        .success(temperatureStatesData, statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())
    let client = HomeAssistantAPIClient(
      session: session,
      climateMetadataLoader: StubClimateMetadataLoader(fails: true)
    )

    let temperatures = try await client.loadTemperatures()

    XCTAssertEqual(temperatures.count, 2)
    XCTAssertNil(temperatures.first(where: { $0.id == "climate.bedroom" })?.icon)
  }

  func testTemperatureLoadingDoesNotWaitForBlockedClimateMetadata() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(Data(#"{"unit_system":{"temperature":"°C"}}"#.utf8), statusCode: 200),
        .success(temperatureStatesData, statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())
    let metadataLoader = NonCooperativeClimateMetadataLoader()
    let client = HomeAssistantAPIClient(
      session: session,
      climateMetadataLoader: metadataLoader,
      climateMetadataTimeout: .milliseconds(50)
    )

    let load = Task {
      try await client.loadTemperatures()
    }
    await fulfillment(of: [metadataLoader.started], timeout: 1)
    let temperatures = try await load.value

    XCTAssertEqual(temperatures.count, 2)
    XCTAssertTrue(metadataLoader.wasCancelled)
    metadataLoader.finish()
  }

  func testCancellingTemperatureLoadCancelsBlockedClimateMetadata() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(Data(#"{"unit_system":{"temperature":"°C"}}"#.utf8), statusCode: 200),
        .success(Data(#"{"unit_system":{"temperature":"°C"}}"#.utf8), statusCode: 200),
        .success(temperatureStatesData, statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())
    let metadataLoader = NonCooperativeClimateMetadataLoader()
    let client = HomeAssistantAPIClient(
      session: session,
      climateMetadataLoader: metadataLoader,
      climateMetadataTimeout: .seconds(10)
    )
    let load = Task {
      try await client.loadTemperatures()
    }
    await fulfillment(of: [metadataLoader.started], timeout: 1)

    load.cancel()

    do {
      _ = try await load.value
      XCTFail("Expected the temperature load to be cancelled.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(metadataLoader.wasCancelled)
    let replacementTemperatures = try await client.loadTemperatures()
    XCTAssertEqual(replacementTemperatures.count, 2)
    XCTAssertEqual(metadataLoader.loadCount, 1)
    metadataLoader.finish()
  }

}

private let temperatureStatesData = Data(
  #"""
  [
    {
      "entity_id": "climate.living_room",
      "state": "cool",
      "attributes": {
        "current_temperature": 23.5,
        "temperature": 24,
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
        "temperature": 22,
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

private struct StubClimateMetadataLoader: HomeAssistantClimateMetadataLoading {
  let icons: [String: String]
  let kinds: [String: HomeAssistantTemperatureReading.Kind]
  let fails: Bool

  init(
    icons: [String: String] = [:],
    kinds: [String: HomeAssistantTemperatureReading.Kind] = [:],
    fails: Bool = false
  ) {
    self.icons = icons
    self.kinds = kinds
    self.fails = fails
  }

  func loadClimateMetadata() async throws -> [String: HomeAssistantClimateMetadata] {
    if fails {
      throw HomeAssistantAPIError.invalidResponse
    }
    return Set(icons.keys).union(kinds.keys).reduce(into: [:]) { metadata, entityID in
      metadata[entityID] = HomeAssistantClimateMetadata(
        icon: icons[entityID],
        kind: kinds[entityID] ?? .other
      )
    }
  }
}

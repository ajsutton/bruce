import XCTest

@testable import Bruce

final class HomeAssistantClimateControlClientTests: XCTestCase {
  func testTurningClimateOnCallsHomeAssistantClimateService() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data("[]".utf8), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    try await HomeAssistantAPIClient(session: session).setPower(
      entityID: "climate.house",
      isOn: true
    )

    let request = try XCTUnwrap(fixture.apiLoader.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.path, "/api/services/climate/turn_on")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Content-Type"),
      "application/json"
    )
    XCTAssertEqual(
      try JSONDecoder().decode(ClimateTarget.self, from: try XCTUnwrap(request.httpBody)),
      ClimateTarget(entityID: "climate.house")
    )
  }

  func testTurningClimateOffCallsHomeAssistantClimateService() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data("[]".utf8), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    try await HomeAssistantAPIClient(session: session).setPower(
      entityID: "climate.house",
      isOn: false
    )

    XCTAssertEqual(
      fixture.apiLoader.requests.first?.url?.path,
      "/api/services/climate/turn_off"
    )
  }

  func testSettingClimateModeCallsHomeAssistantClimateService() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data("[]".utf8), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    try await HomeAssistantAPIClient(session: session).setMode(
      .fanOnly,
      entityID: "climate.house"
    )

    let request = try XCTUnwrap(fixture.apiLoader.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.path, "/api/services/climate/set_hvac_mode")
    XCTAssertEqual(
      try JSONDecoder().decode(ClimateModeRequest.self, from: try XCTUnwrap(request.httpBody)),
      ClimateModeRequest(entityID: "climate.house", hvacMode: "fan_only")
    )
  }

  func testSettingTargetTemperatureCallsHomeAssistantClimateService() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data("[]".utf8), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    try await HomeAssistantAPIClient(session: session).setTargetValue(
      22.5,
      entityID: "climate.living_room"
    )

    let request = try XCTUnwrap(fixture.apiLoader.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.path, "/api/services/climate/set_temperature")
    XCTAssertEqual(
      try JSONDecoder().decode(
        ClimateTemperatureRequest.self,
        from: try XCTUnwrap(request.httpBody)
      ),
      ClimateTemperatureRequest(entityID: "climate.living_room", temperature: 22.5)
    )
  }
}

private struct ClimateTarget: Codable, Equatable {
  let entityID: String

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
  }
}

private struct ClimateModeRequest: Codable, Equatable {
  let entityID: String
  let hvacMode: String

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case hvacMode = "hvac_mode"
  }
}

private struct ClimateTemperatureRequest: Codable, Equatable {
  let entityID: String
  let temperature: Double

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case temperature
  }
}

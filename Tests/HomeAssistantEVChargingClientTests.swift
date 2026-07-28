import XCTest

@testable import Bruce

final class HomeAssistantEVChargingClientTests: XCTestCase {
  func testLoadingChargingModeReadsTheAuthoritativeSelector() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(chargingState("Smart Charging"), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    let mode = try await HomeAssistantAPIClient(session: session).loadEVChargingMode()

    XCTAssertEqual(mode, .smart)
    XCTAssertEqual(
      fixture.apiLoader.requests.first?.url?.path,
      "/api/states/input_select.ev_charging_mode"
    )
  }

  func testLoadingChargingModeRejectsAnUnknownSelectorValue() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(chargingState("Unknown mode"), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(session: session).loadEVChargingMode()
      XCTFail("Expected an unknown charging mode to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testSettingChargingModeUpdatesTheSelectorAndReadsConfirmation() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(Data("[]".utf8), statusCode: 200),
        .success(chargingState("On"), statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())

    let confirmedMode = try await HomeAssistantAPIClient(session: session)
      .setEVChargingMode(.charging)

    XCTAssertEqual(confirmedMode, .charging)
    XCTAssertEqual(
      fixture.apiLoader.requests.map { $0.url?.path },
      [
        "/api/services/input_select/select_option",
        "/api/states/input_select.ev_charging_mode",
      ]
    )
    let request = try XCTUnwrap(fixture.apiLoader.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(
      try JSONDecoder().decode(
        SelectOptionRequest.self,
        from: try XCTUnwrap(request.httpBody)
      ),
      SelectOptionRequest(
        entityID: "input_select.ev_charging_mode",
        option: "On"
      )
    )
  }

  func testSettingChargingModeReportsFailedConfirmationAfterSuccessfulUpdate() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(Data("[]".utf8), statusCode: 200),
        .success(Data("Unavailable".utf8), statusCode: 500),
      ]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(session: session)
        .setEVChargingMode(.charging)
      XCTFail("Expected the failed confirmation to be reported.")
    } catch {
      XCTAssertEqual(
        fixture.apiLoader.requests.map { $0.url?.path },
        [
          "/api/services/input_select/select_option",
          "/api/states/input_select.ev_charging_mode",
        ]
      )
    }
  }

  private func chargingState(_ state: String) -> Data {
    Data(
      """
      {
        "entity_id": "input_select.ev_charging_mode",
        "state": "\(state)",
        "attributes": {
          "friendly_name": "EV Charging",
          "options": ["Off", "Smart Charging", "On"]
        }
      }
      """.utf8
    )
  }
}

private struct SelectOptionRequest: Codable, Equatable {
  let entityID: String
  let option: String

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case option
  }
}

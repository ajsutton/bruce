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

  func testLoadingChargingSnapshotUsesPowerAsEvidenceOfActiveCharging() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(
          chargingSnapshot(
            power: "7024",
            plugStatus: "EV Connected",
            chargerStatus: "Boosting"
          ),
          statusCode: 200
        )
      ]
    )
    try await session.install(fixture.credentials())

    let snapshot = try await HomeAssistantAPIClient(session: session)
      .loadEVChargingSnapshot()

    XCTAssertEqual(snapshot.mode, .smart)
    XCTAssertEqual(snapshot.activity, .charging(powerWatts: 7_024))
    XCTAssertEqual(fixture.apiLoader.requests.first?.url?.path, "/api/states")
  }

  func testLoadingChargingSnapshotDoesNotTreatBoostModeAsActiveCharging() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(
          chargingSnapshot(
            power: "0",
            plugStatus: "EV Disconnected",
            chargerStatus: "Boosting"
          ),
          statusCode: 200
        )
      ]
    )
    try await session.install(fixture.credentials())

    let snapshot = try await HomeAssistantAPIClient(session: session)
      .loadEVChargingSnapshot()

    XCTAssertEqual(snapshot.activity, .notPluggedIn)
  }

  func testLoadingChargingSnapshotExplainsSmartBatteryPause() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(
          chargingSnapshot(
            power: "0",
            plugStatus: "EV Connected",
            chargerStatus: "Paused",
            batteryAllowsCharging: "off"
          ),
          statusCode: 200
        )
      ]
    )
    try await session.install(fixture.credentials())

    let snapshot = try await HomeAssistantAPIClient(session: session)
      .loadEVChargingSnapshot()

    XCTAssertEqual(snapshot.activity, .paused(reason: .homeBattery))
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

  private func chargingSnapshot(
    power: String,
    plugStatus: String,
    chargerStatus: String,
    batteryAllowsCharging: String = "on"
  ) -> Data {
    Data(
      """
      [
        {
          "entity_id": "input_select.ev_charging_mode",
          "state": "Smart Charging",
          "attributes": {}
        },
        {
          "entity_id": "sensor.home_myenergi_home_power_charging",
          "state": "\(power)",
          "attributes": {}
        },
        {
          "entity_id": "sensor.zappi_myenergi_zappi_26482259_plug_status",
          "state": "\(plugStatus)",
          "attributes": {}
        },
        {
          "entity_id": "sensor.zappi_myenergi_zappi_26482259_status",
          "state": "\(chargerStatus)",
          "attributes": {}
        },
        {
          "entity_id": "input_boolean.ev_smart_battery_allows_charging",
          "state": "\(batteryAllowsCharging)",
          "attributes": {}
        },
        {
          "entity_id": "input_boolean.ev_price_allows_charging",
          "state": "on",
          "attributes": {}
        }
      ]
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

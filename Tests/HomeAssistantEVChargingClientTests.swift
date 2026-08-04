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
      "/api/states"
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
    XCTAssertEqual(
      fixture.apiLoader.requests.first?.cachePolicy,
      .reloadIgnoringLocalCacheData
    )
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

  func testLoadingChargingSnapshotRejectsMissingModeTimestamp() async throws {
    let fixture = SessionFixture()
    let missingTimestamp = chargingSnapshot(
      power: "0",
      plugStatus: "EV Connected",
      chargerStatus: "Ready",
      modeLastUpdated: nil
    )
    let session = fixture.makeSession(
      apiResponses: [.success(missingTimestamp, statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(session: session).loadEVChargingSnapshot()
      XCTFail("Expected a charging mode without an ordering timestamp to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Unexpected missing-timestamp error: \(error)")
    }
  }

  func testLoadingChargingSnapshotReadsChargingDecisionInputs() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(
          chargingSnapshot(
            power: "0",
            plugStatus: "EV Connected",
            chargerStatus: "Paused"
          ),
          statusCode: 200
        )
      ]
    )
    try await session.install(fixture.credentials())

    let snapshot = try await HomeAssistantAPIClient(session: session)
      .loadEVChargingSnapshot()

    XCTAssertEqual(snapshot.activity, .paused(reason: nil))
    XCTAssertEqual(
      snapshot.decision,
      HomeAssistantEVChargingDecision(
        isChargingDesired: false,
        overnightSafeChargingMinutes: 108,
        priceAllowsCharging: true,
        currentPriceDollarsPerKilowattHour: 0.24,
        batteryStateOfCharge: 78
      )
    )
  }

  func testLoadingChargingSnapshotKeepsIndependentDecisionValuesWhenDesiredIsMissing()
    async throws
  {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(
          chargingSnapshot(
            power: "0",
            plugStatus: "EV Connected",
            chargerStatus: "Paused",
            decisionStates: chargingDecisionStates(desired: nil, safeMinutes: "108")
          ),
          statusCode: 200
        )
      ]
    )
    try await session.install(fixture.credentials())

    let decision = try await HomeAssistantAPIClient(session: session)
      .loadEVChargingSnapshot().decision

    XCTAssertNil(decision.isChargingDesired)
    XCTAssertEqual(decision.overnightSafeChargingMinutes, 108)
    XCTAssertEqual(decision.batteryStateOfCharge, 78)
  }

  func testLoadingChargingSnapshotRejectsUnboundedSafeChargingTime() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(
          chargingSnapshot(
            power: "0",
            plugStatus: "EV Connected",
            chargerStatus: "Paused",
            decisionStates: chargingDecisionStates(
              desired: "off",
              safeMinutes: "1e300"
            )
          ),
          statusCode: 200
        )
      ]
    )
    try await session.install(fixture.credentials())

    let decision = try await HomeAssistantAPIClient(session: session)
      .loadEVChargingSnapshot().decision

    XCTAssertNil(decision.overnightSafeChargingMinutes)
    XCTAssertEqual(decision.batteryStateOfCharge, 78)
  }

  func testSettingChargingModeUpdatesTheSelectorAndReadsConfirmation() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(chargingState("Smart Charging"), statusCode: 200),
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
        "/api/states",
        "/api/services/input_select/select_option",
        "/api/states",
      ]
    )
    let request = try XCTUnwrap(fixture.apiLoader.requests.dropFirst().first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(
      try JSONDecoder().decode(
        SelectOptionRequest.self,
        from: try XCTUnwrap(request.httpBody)
      ),
      SelectOptionRequest(
        entityID: "input_select.house_car_charging",
        option: "On"
      )
    )
  }

  func testSettingChargingModeReportsFailedConfirmationAfterSuccessfulUpdate() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(chargingState("Smart Charging"), statusCode: 200),
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
          "/api/states",
          "/api/services/input_select/select_option",
          "/api/states",
        ]
      )
    }
  }

}

private func chargingState(_ state: String) -> Data {
  Data(
    """
    [
      {
        "entity_id": "input_select.house_car_charging",
        "state": "\(state)",
        "attributes": {
          "friendly_name": "EV Charging",
          "options": ["Off", "Smart Charging", "On"]
        }
      }
    ]
    """.utf8
  )
}

private func chargingSnapshot(
  power: String,
  plugStatus: String,
  chargerStatus: String,
  modeLastUpdated: String? = "2026-07-28T01:02:03Z",
  decisionStates: String = chargingDecisionStates()
) -> Data {
  let entities = [
    chargingModeState(lastUpdated: modeLastUpdated),
    chargerStates(power: power, plugStatus: plugStatus, chargerStatus: chargerStatus),
    decisionStates,
  ]
  return Data("[\(entities.joined(separator: ","))]".utf8)
}

private func chargingModeState(lastUpdated: String?) -> String {
  let orderingTimestamp = lastUpdated.map { ", \"last_updated\": \"\($0)\"" } ?? ""
  return """
    {
      "entity_id": "input_select.ev_charging_mode",
      "state": "Smart Charging",
      "attributes": {"options": ["Off", "Smart Charging", "On"]}
      \(orderingTimestamp)
    }
    """
}

private func chargerStates(power: String, plugStatus: String, chargerStatus: String) -> String {
  """
  {
    "entity_id": "sensor.home_myenergi_home_power_charging",
    "state": "\(power)",
    "attributes": {"device_class": "power", "unit_of_measurement": "W"}
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
  }
  """
}

private func chargingDecisionStates(
  desired: String? = "off",
  safeMinutes: String = "108"
) -> String {
  let desiredState =
    desired.map {
      """
      {
        "entity_id": "input_boolean.ev_charging_desired",
        "state": "\($0)",
        "attributes": {}
      },
      """
    } ?? ""
  return """
    \(desiredState)
    {
      "entity_id": "input_boolean.ev_price_allows_charging",
      "state": "on",
      "attributes": {}
    },
    {
      "entity_id": "sensor.ev_overnight_safe_charging_time",
      "state": "\(safeMinutes)",
      "attributes": {"device_class": "duration", "unit_of_measurement": "min"}
    },
    {
      "entity_id": "sensor.01krmdgkh60wyckeepvgtbbgv3_general_price",
      "state": "0.24",
      "attributes": {}
    },
    {
      "entity_id": "sensor.sigen_plant_battery_state_of_charge",
      "state": "78",
      "attributes": {"unit_of_measurement": "%"}
    }
    """
}

private struct SelectOptionRequest: Codable, Equatable {
  let entityID: String
  let option: String

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case option
  }
}

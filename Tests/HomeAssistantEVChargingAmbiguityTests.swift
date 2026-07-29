import XCTest

@testable import Bruce

final class HomeAssistantEVChargingAmbiguityTests: XCTestCase {
  func testLoadingChargingModeRejectsMultipleMatchingSelectors() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(ambiguousChargingState(), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(session: session).loadEVChargingMode()
      XCTFail("Expected ambiguous charging selectors to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testLoadingChargingSnapshotDoesNotCombineAmbiguousPlugStatuses() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(ambiguousPlugStates(), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    let snapshot = try await HomeAssistantAPIClient(session: session)
      .loadEVChargingSnapshot()

    XCTAssertEqual(snapshot.activity, .unavailable)
  }

  func testLoadingChargingSnapshotDoesNotCombineCrossDeviceStatus() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(crossDeviceStates(), statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    let snapshot = try await HomeAssistantAPIClient(session: session)
      .loadEVChargingSnapshot()

    XCTAssertEqual(snapshot.activity, .connected)
  }

  private func ambiguousChargingState() -> Data {
    Data(
      """
      [
        \(selector("input_select.house_car_charging")),
        \(selector("input_select.garage_ev_charging"))
      ]
      """.utf8
    )
  }

  private func ambiguousPlugStates() -> Data {
    Data(
      """
      [
        \(selector("input_select.ev_charging_mode", timestamp: true)),
        {
          "entity_id": "sensor.home_myenergi_home_power_charging",
          "state": "0",
          "attributes": {
            "device_class": "power",
            "unit_of_measurement": "W"
          }
        },
        {
          "entity_id": "sensor.zappi_ev_plug_status",
          "state": "EV Connected",
          "attributes": {}
        },
        {
          "entity_id": "sensor.garage_ev_plug_status",
          "state": "EV Disconnected",
          "attributes": {}
        }
      ]
      """.utf8
    )
  }

  private func crossDeviceStates() -> Data {
    Data(
      """
      [
        \(selector("input_select.ev_charging_mode", timestamp: true)),
        {
          "entity_id": "sensor.zappi_myenergi_zappi_26482259_plug_status",
          "state": "EV Connected",
          "attributes": {}
        },
        {
          "entity_id": "sensor.other_charger_status",
          "state": "Completed",
          "attributes": {}
        }
      ]
      """.utf8
    )
  }

  private func selector(_ entityID: String, timestamp: Bool = false) -> String {
    let lastUpdated =
      timestamp
      ? ",\n  \"last_updated\": \"2026-07-28T01:02:03Z\""
      : ""
    return """
      {
        "entity_id": "\(entityID)",
        "state": "Smart Charging",
        "attributes": {
          "options": ["Off", "Smart Charging", "On"]
        }\(lastUpdated)
      }
      """
  }
}

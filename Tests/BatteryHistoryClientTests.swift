import XCTest

@testable import Bruce

final class BatteryHistoryClientTests: XCTestCase {
  func testLoadingBatteryHistoryRequestsAndDecodesTheLast24Hours() async throws {
    let fixture = SessionFixture()
    let end = try date("2026-07-30T06:00:00Z")
    let session = fixture.makeSession(
      apiResponses: [.success(batteryHistory, statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    let history = try await HomeAssistantAPIClient(
      session: session,
      now: { end }
    ).loadHomeEnergyBatteryHistory()

    let start = try date("2026-07-29T06:00:00Z")
    XCTAssertEqual(history.interval, DateInterval(start: start, end: end))
    XCTAssertEqual(
      history.readings,
      [
        HomeEnergyBatteryHistory.Reading(
          timestamp: start,
          stateOfCharge: 34
        ),
        HomeEnergyBatteryHistory.Reading(
          timestamp: try date("2026-07-29T10:00:00Z"),
          stateOfCharge: 41
        ),
        HomeEnergyBatteryHistory.Reading(
          timestamp: try date("2026-07-29T12:00:00Z"),
          stateOfCharge: nil
        ),
      ]
    )

    try assertHistoryRequest(
      fixture.apiLoader.requests.first?.url,
      start: start,
      end: end
    )
  }

  func testLoadingBatteryHistoryRejectsAnUnidentifiedSeries() async throws {
    let fixture = SessionFixture()
    let end = try date("2026-07-30T06:00:00Z")
    let session = fixture.makeSession(
      apiResponses: [
        .success(
          Data(
            #"""
            [[{"state":"34","last_changed":"2026-07-29T10:00:00Z"}]]
            """#.utf8
          ),
          statusCode: 200
        )
      ]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(
        session: session,
        now: { end }
      ).loadHomeEnergyBatteryHistory()
      XCTFail("Expected unidentified battery history to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Unexpected battery history error: \(error)")
    }
  }

  func testLoadingBatteryHistoryRequiresIdentityOnTheFirstState() async throws {
    try await assertInvalidHistory(
      Data(
        """
        [[
          {"state":"34","last_changed":"2026-07-29T10:00:00Z"},
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.batteryStateOfChargeEntityID)",
            "state":"41",
            "last_changed":"2026-07-29T11:00:00Z"
          }
        ]]
        """.utf8
      )
    )
  }

  func testLoadingBatteryHistoryRejectsAConflictingLaterIdentity() async throws {
    try await assertInvalidHistory(
      Data(
        """
        [[
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.batteryStateOfChargeEntityID)",
            "state":"34",
            "last_changed":"2026-07-29T10:00:00Z"
          },
          {
            "entity_id":"sensor.not_the_battery",
            "state":"41",
            "last_changed":"2026-07-29T11:00:00Z"
          }
        ]]
        """.utf8
      )
    )
  }

  private func assertInvalidHistory(_ data: Data) async throws {
    let fixture = SessionFixture()
    let end = try date("2026-07-30T06:00:00Z")
    let session = fixture.makeSession(
      apiResponses: [.success(data, statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    do {
      _ = try await HomeAssistantAPIClient(
        session: session,
        now: { end }
      ).loadHomeEnergyBatteryHistory()
      XCTFail("Expected malformed battery history to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Unexpected battery history error: \(error)")
    }
  }

  private func assertHistoryRequest(
    _ requestURL: URL?,
    start: Date,
    end: Date
  ) throws {
    let requestURL = try XCTUnwrap(requestURL)
    let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    XCTAssertEqual(
      requestURL.path,
      "/api/history/period/\(start.formatted(timestampStyle))"
    )
    let queryItems =
      try XCTUnwrap(
        URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
      ).queryItems ?? []
    XCTAssertEqual(
      queryItems.first(where: { $0.name == "end_time" })?.value,
      end.formatted(timestampStyle)
    )
    XCTAssertEqual(
      queryItems.first(where: { $0.name == "filter_entity_id" })?.value,
      HomeAssistantHomeEnergySnapshot.batteryStateOfChargeEntityID
    )
    XCTAssertTrue(queryItems.contains { $0.name == "minimal_response" })
    XCTAssertTrue(queryItems.contains { $0.name == "no_attributes" })
  }

  private var batteryHistory: Data {
    Data(
      """
      [
        [
          {
            "entity_id": "\(HomeAssistantHomeEnergySnapshot.batteryStateOfChargeEntityID)",
            "state": "34",
            "last_changed": "2026-07-29T05:30:00Z"
          },
          {
            "state": "41",
            "last_changed": "2026-07-29T10:00:00Z"
          },
          {
            "state": "unknown",
            "last_changed": "2026-07-29T12:00:00Z"
          }
        ]
      ]
      """.utf8
    )
  }

  private func date(_ value: String) throws -> Date {
    try Date(
      value,
      strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    )
  }
}

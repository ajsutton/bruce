import XCTest

@testable import Bruce

final class HomeEnergyFlowHistoryClientTests: XCTestCase {
  func testLoadingFlowHistoryRequestsAndNormalizesTheLast24Hours() async throws {
    let fixture = SessionFixture()
    let end = try date("2026-07-30T06:00:00Z")
    let session = fixture.makeSession(
      apiResponses: [.success(flowHistory, statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    let history = try await HomeAssistantAPIClient(
      session: session,
      now: { end }
    ).loadHomeEnergyFlowHistory()

    let start = try date("2026-07-29T06:00:00Z")
    XCTAssertEqual(history.interval, DateInterval(start: start, end: end))
    XCTAssertEqual(
      history.readings,
      [
        reading(.battery, at: start, kilowatts: -2.5),
        reading(.grid, at: start, kilowatts: -1.5),
        reading(.homeUsage, at: start, kilowatts: 2),
        reading(.pvGeneration, at: start, kilowatts: 8),
        reading(
          .battery,
          at: try date("2026-07-29T10:00:00Z"),
          kilowatts: 1
        ),
        reading(
          .grid,
          at: try date("2026-07-29T11:00:00Z"),
          kilowatts: 3
        ),
        reading(
          .pvGeneration,
          at: try date("2026-07-29T12:00:00Z"),
          kilowatts: nil
        ),
      ]
    )
    try assertHistoryRequest(
      fixture.apiLoader.requests.first?.url,
      start: start,
      end: end
    )
  }

  func testLoadingFlowHistoryRejectsAnUnidentifiedSeries() async throws {
    let fixture = SessionFixture()
    let end = try date("2026-07-30T06:00:00Z")
    let session = fixture.makeSession(
      apiResponses: [
        .success(
          Data(
            #"""
            [[{"entity_id":"sensor.not_a_flow","state":"2","last_changed":"2026-07-29T10:00:00Z"}]]
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
      ).loadHomeEnergyFlowHistory()
      XCTFail("Expected unidentified flow history to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Unexpected flow history error: \(error)")
    }
  }

  func testDecodingFlowHistorySamplesDenseSeriesAtChartResolution() throws {
    let start = try date("2026-07-29T06:00:00Z")
    let end = start.addingTimeInterval(10 * 60)
    let history = try HomeEnergyFlowHistory(
      data: try denseFlowHistory(from: start, through: end),
      interval: DateInterval(start: start, end: end)
    )

    for series in HomeEnergyFlowHistory.Series.allCases {
      let readings = history.readings.filter { $0.series == series }
      XCTAssertEqual(readings.first?.timestamp, start)
      XCTAssertEqual(readings.last?.timestamp, end)
      XCTAssertLessThanOrEqual(readings.count, 7)
    }
  }

  func testDecodingFlowHistoryPreservesAvailabilityTransitionsWithinASampleWindow()
    throws
  {
    let start = try date("2026-07-29T06:00:00Z")
    let history = try HomeEnergyFlowHistory(
      data: Data(
        """
        [[
          {
            "entity_id": "\(HomeAssistantHomeEnergySnapshot.gridPowerEntityID)",
            "state": "1",
            "last_changed": "2026-07-29T06:00:00Z"
          },
          {
            "state": "unavailable",
            "last_changed": "2026-07-29T06:00:30Z"
          },
          {
            "state": "-2",
            "last_changed": "2026-07-29T06:01:00Z"
          }
        ]]
        """.utf8
      ),
      interval: DateInterval(
        start: start,
        end: start.addingTimeInterval(HomeEnergyHistorySampling.interval)
      )
    )

    XCTAssertEqual(
      history.readings,
      [
        reading(.grid, at: start, kilowatts: 1),
        reading(.grid, at: start.addingTimeInterval(30), kilowatts: nil),
        reading(.grid, at: start.addingTimeInterval(60), kilowatts: -2),
      ]
    )
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
      [
        HomeAssistantHomeEnergySnapshot.pvPowerEntityID,
        HomeAssistantHomeEnergySnapshot.homeConsumptionEntityID,
        HomeAssistantHomeEnergySnapshot.gridPowerEntityID,
        HomeAssistantHomeEnergySnapshot.batteryPowerEntityID,
      ].joined(separator: ",")
    )
    XCTAssertTrue(queryItems.contains { $0.name == "minimal_response" })
    XCTAssertTrue(queryItems.contains { $0.name == "no_attributes" })
  }

  private func reading(
    _ series: HomeEnergyFlowHistory.Series,
    at timestamp: Date,
    kilowatts: Double?
  ) -> HomeEnergyFlowHistory.Reading {
    HomeEnergyFlowHistory.Reading(
      series: series,
      timestamp: timestamp,
      kilowatts: kilowatts
    )
  }

  private var flowHistory: Data {
    Data(
      """
      [
        [
          {
            "entity_id": "\(HomeAssistantHomeEnergySnapshot.pvPowerEntityID)",
            "state": "8",
            "last_changed": "2026-07-29T05:30:00Z"
          },
          {
            "state": "-1",
            "last_changed": "2026-07-29T12:00:00Z"
          }
        ],
        [
          {
            "entity_id": "\(HomeAssistantHomeEnergySnapshot.homeConsumptionEntityID)",
            "state": "2",
            "last_changed": "2026-07-29T05:40:00Z"
          }
        ],
        [
          {
            "entity_id": "\(HomeAssistantHomeEnergySnapshot.gridPowerEntityID)",
            "state": "-1.5",
            "last_changed": "2026-07-29T05:50:00Z"
          },
          {
            "state": "3",
            "last_changed": "2026-07-29T11:00:00Z"
          }
        ],
        [
          {
            "entity_id": "\(HomeAssistantHomeEnergySnapshot.batteryPowerEntityID)",
            "state": "2.5",
            "last_changed": "2026-07-29T05:55:00Z"
          },
          {
            "state": "-1",
            "last_changed": "2026-07-29T10:00:00Z"
          }
        ]
      ]
      """.utf8
    )
  }

  private func denseFlowHistory(
    from start: Date,
    through end: Date
  ) throws -> Data {
    let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    let entityIDs = [
      HomeAssistantHomeEnergySnapshot.pvPowerEntityID,
      HomeAssistantHomeEnergySnapshot.homeConsumptionEntityID,
      HomeAssistantHomeEnergySnapshot.gridPowerEntityID,
      HomeAssistantHomeEnergySnapshot.batteryPowerEntityID,
    ]
    let groups = entityIDs.map { entityID in
      stride(from: 0.0, through: end.timeIntervalSince(start), by: 5).map { offset in
        var state: [String: String] = [
          "state": "\(offset)",
          "last_changed": start.addingTimeInterval(offset).formatted(timestampStyle),
        ]
        if offset == 0 {
          state["entity_id"] = entityID
        }
        return state
      }
    }
    return try JSONSerialization.data(withJSONObject: groups)
  }

  private func date(_ value: String) throws -> Date {
    try Date(
      value,
      strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    )
  }
}

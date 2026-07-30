import XCTest

@testable import Bruce

final class HomeAssistantHomeEnergyClientTests: XCTestCase {
  func testLoadingHomeEnergySnapshotReadsSigenergyPowerFlow() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(homeEnergyStates, statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    let snapshot = try await HomeAssistantAPIClient(session: session)
      .loadHomeEnergySnapshot()

    XCTAssertEqual(
      snapshot,
      HomeAssistantHomeEnergySnapshot(
        pvPowerKilowatts: 8.4,
        batteryStateOfCharge: 76,
        batteryPowerKilowatts: 2.6,
        homeConsumptionKilowatts: 3.1,
        gridPowerKilowatts: -2.7,
        generalPriceDollarsPerKilowattHour: 0.341,
        feedInPriceDollarsPerKilowattHour: 0.127
      )
    )
    XCTAssertEqual(fixture.apiLoader.requests.first?.url?.path, "/api/states")
  }

  func testLoadingHomeEnergySnapshotLeavesInvalidReadingsUnavailable() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(invalidHomeEnergyStates, statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    let snapshot = try await HomeAssistantAPIClient(session: session)
      .loadHomeEnergySnapshot()

    XCTAssertEqual(snapshot, .unavailable)
  }

  func testLoadingPriceHistoryRequestsAndDecodesTheLast24Hours() async throws {
    let fixture = SessionFixture()
    let end = try date("2026-07-30T06:00:00Z")
    let session = fixture.makeSession(
      apiResponses: [.success(priceHistory, statusCode: 200)]
    )
    try await session.install(fixture.credentials())

    let history = try await HomeAssistantAPIClient(
      session: session,
      now: { end }
    ).loadHomeEnergyPriceHistory()

    let start = try date("2026-07-29T06:00:00Z")
    XCTAssertEqual(history.interval, DateInterval(start: start, end: end))
    XCTAssertEqual(history.readings, try expectedPriceHistory(start: start))

    try assertHistoryRequest(
      fixture.apiLoader.requests.first?.url,
      start: start,
      end: end,
      entityIDs: [
        HomeAssistantHomeEnergySnapshot.generalPriceEntityID,
        HomeAssistantHomeEnergySnapshot.feedInPriceEntityID,
      ]
    )
  }

  func testLoadingPriceHistoryRejectsAnUnidentifiedSeries() async throws {
    let fixture = SessionFixture()
    let end = try date("2026-07-30T06:00:00Z")
    let session = fixture.makeSession(
      apiResponses: [
        .success(
          Data(
            #"""
            [[{"state":"0.22","last_changed":"2026-07-29T10:00:00Z"}]]
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
      ).loadHomeEnergyPriceHistory()
      XCTFail("Expected unidentified price history to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Unexpected price history error: \(error)")
    }
  }
}

extension HomeAssistantHomeEnergyClientTests {
  private func assertHistoryRequest(
    _ requestURL: URL?,
    start: Date,
    end: Date,
    entityIDs: [String]
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
      entityIDs.joined(separator: ",")
    )
    XCTAssertTrue(queryItems.contains { $0.name == "minimal_response" })
    XCTAssertTrue(queryItems.contains { $0.name == "no_attributes" })
  }

  private func expectedPriceHistory(
    start: Date
  ) throws -> [HomeEnergyPriceHistory.Reading] {
    [
      .init(tariff: .feedIn, timestamp: start, dollarsPerKilowattHour: 0.07),
      .init(tariff: .general, timestamp: start, dollarsPerKilowattHour: 0.22),
      .init(
        tariff: .general,
        timestamp: try date("2026-07-29T10:00:00Z"),
        dollarsPerKilowattHour: 0.41
      ),
      .init(
        tariff: .feedIn,
        timestamp: try date("2026-07-29T12:00:00Z"),
        dollarsPerKilowattHour: 0.13
      ),
      .init(
        tariff: .general,
        timestamp: try date("2026-07-29T14:00:00Z"),
        dollarsPerKilowattHour: nil
      ),
      .init(
        tariff: .feedIn,
        timestamp: try date("2026-07-29T15:00:00Z"),
        dollarsPerKilowattHour: nil
      ),
    ]
  }

  private var homeEnergyStates: Data {
    states(
      solarPower: "8.4",
      battery: (charge: "76", power: "-2.6"),
      usage: "3.1",
      grid: "-2.7",
      prices: (general: "0.341", feedIn: "0.127")
    )
  }

  private var invalidHomeEnergyStates: Data {
    states(
      solarPower: "-1",
      battery: (charge: "101", power: "unknown"),
      usage: "unknown",
      grid: "unavailable",
      prices: (general: "NaN", feedIn: "infinite")
    )
  }

  private var priceHistory: Data {
    Data(
      """
      [
        [
          {
            "entity_id": "\(HomeAssistantHomeEnergySnapshot.generalPriceEntityID)",
            "state": "0.22",
            "last_changed": "2026-07-29T05:30:00Z"
          },
          {
            "state": "0.41",
            "last_changed": "2026-07-29T10:00:00Z"
          },
          {
            "state": "unavailable",
            "last_changed": "2026-07-29T14:00:00Z"
          }
        ],
        [
          {
            "entity_id": "\(HomeAssistantHomeEnergySnapshot.feedInPriceEntityID)",
            "state": "0.07",
            "last_changed": "2026-07-29T05:45:00Z"
          },
          {
            "state": "0.13",
            "last_changed": "2026-07-29T12:00:00Z"
          },
          {
            "state": "unknown",
            "last_changed": "2026-07-29T15:00:00Z"
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

  private func states(
    solarPower: String,
    battery: (charge: String, power: String),
    usage: String,
    grid: String,
    prices: (general: String, feedIn: String)
  ) -> Data {
    Data(
      """
      [
        {
          "entity_id": "sensor.sigen_plant_pv_power",
          "state": "\(solarPower)",
          "attributes": {}
        },
        {
          "entity_id": "sensor.sigen_plant_battery_state_of_charge",
          "state": "\(battery.charge)",
          "attributes": {}
        },
        {
          "entity_id": "sensor.sigen_plant_battery_power",
          "state": "\(battery.power)",
          "attributes": {}
        },
        {
          "entity_id": "sensor.sigen_plant_consumed_power",
          "state": "\(usage)",
          "attributes": {}
        },
        {
          "entity_id": "sensor.sigen_plant_grid_active_power",
          "state": "\(grid)",
          "attributes": {}
        },
        {
          "entity_id": "sensor.01krmdgkh60wyckeepvgtbbgv3_general_price",
          "state": "\(prices.general)",
          "attributes": {}
        },
        {
          "entity_id": "sensor.01krmdgkh60wyckeepvgtbbgv3_feed_in_price",
          "state": "\(prices.feedIn)",
          "attributes": {}
        }
      ]
      """.utf8
    )
  }
}

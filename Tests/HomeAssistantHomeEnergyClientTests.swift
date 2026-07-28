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

  private var homeEnergyStates: Data {
    states(
      solarPower: "8.4",
      battery: "76",
      usage: "3.1",
      grid: "-2.7",
      prices: (general: "0.341", feedIn: "0.127")
    )
  }

  private var invalidHomeEnergyStates: Data {
    states(
      solarPower: "-1",
      battery: "101",
      usage: "unknown",
      grid: "unavailable",
      prices: (general: "NaN", feedIn: "infinite")
    )
  }

  private func states(
    solarPower: String,
    battery: String,
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
          "state": "\(battery)",
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
          "entity_id": "sensor.electricity_general_price",
          "state": "\(prices.general)",
          "attributes": {}
        },
        {
          "entity_id": "sensor.electricity_feed_in_price",
          "state": "\(prices.feedIn)",
          "attributes": {}
        }
      ]
      """.utf8
    )
  }
}

import XCTest

@testable import Bruce

final class BruceSiriServiceTests: XCTestCase {
  func testSolarQueryFetchesANewReadingEveryTime() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [
      .success(energyStates(solar: "2.4"), statusCode: 200),
      .success(energyStates(solar: "5.6"), statusCode: 200),
    ])
    try await session.install(fixture.credentials())
    let service = service(session: session)

    let first = try await service.solarGeneration()
    let second = try await service.solarGeneration()

    XCTAssertEqual(first, 2.4)
    XCTAssertEqual(second, 5.6)
    XCTAssertEqual(fixture.apiLoader.requests.count, 2)
    XCTAssertTrue(
      fixture.apiLoader.requests.allSatisfy {
        $0.cachePolicy == .reloadIgnoringLocalCacheData
      })
  }

  func testBatteryQueryReturnsTheHomeBatteryPercentage() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [.success(energyStates(), statusCode: 200)])
    try await session.install(fixture.credentials())

    let level = try await service(session: session).batteryLevel()

    XCTAssertEqual(level, 76)
  }

  func testElectricityQueryReturnsInstantaneousConsumptionInKilowatts() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [.success(energyStates(), statusCode: 200)])
    try await session.install(fixture.credentials())

    let usage = try await service(session: session).electricityUsage()

    XCTAssertEqual(usage, 3.1)
  }

  func testUnavailableSolarDoesNotReturnZeroOrAnotherReading() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [
      .success(energyStates(solar: "unavailable"), statusCode: 200)
    ])
    try await session.install(fixture.credentials())

    do {
      _ = try await service(session: session).solarGeneration()
      XCTFail("Expected an unavailable reading.")
    } catch BruceSiriError.unavailable {
    }
  }

  func testMissingConnectionAsksUserToConnectInBruce() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])

    do {
      _ = try await service(session: session).batteryLevel()
      XCTFail("Expected a sign-in error.")
    } catch BruceSiriError.signInRequired {
    }
    XCTAssertTrue(fixture.apiLoader.requests.isEmpty)
  }

  func testPreparationRestoresCredentialsBeforeRequestingData() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [.success(energyStates(), statusCode: 200)])
    await fixture.store.save(fixture.credentials())
    let client = HomeAssistantAPIClient(session: session)
    let service = BruceSiriService(
      energy: client, charger: client,
      prepare: {
        _ = try await session.restore()
      })

    let level = try await service.batteryLevel()

    XCTAssertEqual(level, 76)
  }

  func testServerFailureDoesNotReturnACachedReading() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [
      .success(Data(), statusCode: 500)
    ])
    try await session.install(fixture.credentials())

    do {
      _ = try await service(session: session).solarGeneration()
      XCTFail("Expected a connection error.")
    } catch BruceSiriError.connectionUnavailable {
    }
  }

  func testChargerModeQueryDoesNotClaimTheVehicleIsCharging() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [
      .success(chargerStates(mode: "On"), statusCode: 200)
    ])
    try await session.install(fixture.credentials())

    let mode = try await service(session: session).chargerMode()

    XCTAssertEqual(mode, .charging)
  }

  func testUnknownChargerModeIsReportedAsUnavailable() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [
      .success(chargerStates(mode: "unavailable"), statusCode: 200)
    ])
    try await session.install(fixture.credentials())

    do {
      _ = try await service(session: session).chargerMode()
      XCTFail("Expected an unavailable charger mode.")
    } catch BruceSiriError.unavailable {
    }
  }

  func testAbsentChargerIsReportedAsUnavailable() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [.success(Data("[]".utf8), statusCode: 200)])
    try await session.install(fixture.credentials())

    do {
      _ = try await service(session: session).chargerMode()
      XCTFail("Expected an unavailable charger mode.")
    } catch BruceSiriError.unavailable {
    }
  }

  func testChargerStatusReportsUnpluggedEvenWhenModeIsOn() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [
      .success(chargerStates(mode: "On"), statusCode: 200)
    ])
    try await session.install(fixture.credentials())

    let status = try await service(session: session).chargerStatus()

    XCTAssertEqual(status, .notPluggedIn)
  }

  func testSettingChargerModeChecksServerStateAfterWriting() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [
      .success(chargerStates(mode: "Off"), statusCode: 200),
      .success(Data("[]".utf8), statusCode: 200),
      .success(chargerStates(mode: "Smart Charging"), statusCode: 200),
    ])
    try await session.install(fixture.credentials())

    try await service(session: session).setChargerMode(.smart)

    XCTAssertEqual(fixture.apiLoader.requests.map(\.httpMethod), ["GET", "POST", "GET"])
    let request = try XCTUnwrap(fixture.apiLoader.requests.first { $0.httpMethod == "POST" })
    XCTAssertEqual(request.url?.path, "/api/services/input_select/select_option")
    let body = try XCTUnwrap(request.httpBody)
    let parameters = try JSONDecoder().decode([String: String].self, from: body)
    XCTAssertEqual(
      parameters, ["entity_id": "input_select.ev_charging_mode", "option": "Smart Charging"])
  }

  func testModeChangeIsNotReportedAsSuccessfulWhenReadbackDisagrees() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [
      .success(chargerStates(mode: "Off"), statusCode: 200),
      .success(Data("[]".utf8), statusCode: 200),
      .success(chargerStates(mode: "Off"), statusCode: 200),
    ])
    try await session.install(fixture.credentials())

    do {
      try await service(session: session).setChargerMode(.smart)
      XCTFail("Expected the unconfirmed change to fail.")
    } catch BruceSiriError.modeNotConfirmed {
    }
  }

  func testFailedReadbackAfterModeWriteReportsAnUnconfirmedChange() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [
      .success(chargerStates(mode: "Off"), statusCode: 200),
      .success(Data("[]".utf8), statusCode: 200),
      .success(Data(), statusCode: 500),
    ])
    try await session.install(fixture.credentials())

    do {
      try await service(session: session).setChargerMode(.smart)
      XCTFail("Expected an unconfirmed change after a failed readback.")
    } catch BruceSiriError.modeNotConfirmed {
    }
    XCTAssertEqual(fixture.apiLoader.requests.filter { $0.httpMethod == "POST" }.count, 1)
  }

  func testCancelledRequestDoesNotReachHomeAssistant() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    let client = HomeAssistantAPIClient(session: session)
    let service = BruceSiriService(
      energy: client, charger: client,
      prepare: {
        throw CancellationError()
      })

    do {
      _ = try await service.batteryLevel()
      XCTFail("Expected cancellation to propagate.")
    } catch is CancellationError {
    }
    XCTAssertTrue(fixture.apiLoader.requests.isEmpty)
  }

  func testCancellingAnInFlightQueryCancelsItsDataLoad() async throws {
    let delay = ControlledHomeEnergyDelay(delayCount: 1)
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    let service = BruceSiriService(
      energy: SuspendedSiriEnergyLoader(delay: delay),
      charger: HomeAssistantAPIClient(session: session),
      prepare: {}
    )
    let query = Task { try await service.solarGeneration() }
    await fulfillment(of: [delay.started(at: 0)], timeout: 1)

    query.cancel()

    await fulfillment(of: [delay.completed(at: 0)], timeout: 1)
    do {
      _ = try await query.value
      XCTFail("Expected cancellation to propagate.")
    } catch is CancellationError {
    }
  }

  func testDeadlineCancelsTheDataLoadAndReportsUnavailableConnection() async throws {
    let load = ControlledHomeEnergyDelay(delayCount: 1)
    let deadline = ControlledHomeEnergyDelay(delayCount: 1)
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    let service = BruceSiriService(
      energy: SuspendedSiriEnergyLoader(delay: load),
      charger: HomeAssistantAPIClient(session: session),
      prepare: {},
      waitForTimeout: { try await deadline.sleep(.seconds(12)) }
    )
    let query = Task { try await service.solarGeneration() }
    await fulfillment(of: [load.started(at: 0), deadline.started(at: 0)], timeout: 1)

    deadline.finish(0)

    await fulfillment(of: [load.completed(at: 0)], timeout: 1)
    do {
      _ = try await query.value
      XCTFail("Expected the deadline to end the query.")
    } catch BruceSiriError.connectionUnavailable {
    }
  }

  private func service(session: HomeAssistantSession) -> BruceSiriService {
    let client = HomeAssistantAPIClient(session: session)
    return BruceSiriService(energy: client, charger: client, prepare: {})
  }

  private func energyStates(solar: String = "8.4") -> Data {
    Data(
      """
      [
        {"entity_id":"sensor.sigen_plant_pv_power","state":"\(solar)","attributes":{}},
        {"entity_id":"sensor.sigen_plant_battery_state_of_charge","state":"76","attributes":{}},
        {"entity_id":"sensor.sigen_plant_consumed_power","state":"3.1","attributes":{}}
      ]
      """.utf8
    )
  }

  private func chargerStates(mode: String) -> Data {
    Data(
      """
      [
        {"entity_id":"input_select.ev_charging_mode","state":"\(mode)",
         "last_updated":"2026-09-26T01:00:00Z",
         "attributes":{"options":["Off","Smart Charging","On"]}},
        {"entity_id":"sensor.ev_plug_status","state":"EV Disconnected","attributes":{}}
      ]
      """.utf8
    )
  }
}

private struct SuspendedSiriEnergyLoader: HomeAssistantHomeEnergyLoading {
  let delay: ControlledHomeEnergyDelay

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    try await delay.sleep(.seconds(12))
    return .unavailable
  }
}

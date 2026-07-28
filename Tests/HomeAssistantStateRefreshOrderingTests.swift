import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantStateRefreshOrderingTests: XCTestCase {
  func testRefreshCannotRollBackNewerLiveState() async throws {
    let setup = try await refreshSetup()
    let probe = setup.probe
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    await fulfillment(of: [setup.firstConnection.blockedReceiveStarted], timeout: 1)
    setup.firstConnection.succeed(
      with: stateChangedEvent(entityID: "climate.bedroom", value: 25)
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)

    let refreshed = await setup.hub.refresh()
    XCTAssertTrue(refreshed)
    await fulfillment(of: [probe.received(at: 3)], timeout: 1)

    let state = try XCTUnwrap(try probe.value(at: 3).states.first)
    let reading = try XCTUnwrap(
      state.temperatureReading(unit: "°C", metadata: nil)
    )
    XCTAssertEqual(reading.value, 25)
    setup.secondConnection.cancel()
  }

  func testRefreshCannotResurrectRemovedState() async throws {
    let setup = try await refreshSetup()
    let probe = setup.probe
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    await fulfillment(of: [setup.firstConnection.blockedReceiveStarted], timeout: 1)
    setup.firstConnection.succeed(
      with: stateRemovedEvent(
        entityID: "climate.bedroom",
        oldLastUpdated: "2026-07-27T01:03:04Z"
      )
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)

    let refreshed = await setup.hub.refresh()
    XCTAssertTrue(refreshed)
    await fulfillment(of: [probe.received(at: 3)], timeout: 1)

    XCTAssertTrue(try probe.value(at: 3).states.isEmpty)
    setup.secondConnection.cancel()
  }

  func testServerSwitchDoesNotRetainNewerStateFromPreviousServer() async throws {
    try await assertServerSwitchDoesNotRetainNewerState(usesInstanceID: true)
  }

  func testEndpointSwitchDoesNotRetainNewerStateFromPreviousServer() async throws {
    try await assertServerSwitchDoesNotRetainNewerState(usesInstanceID: false)
  }

  func testServerSwitchDoesNotRetainRemovalFromPreviousServer() async throws {
    try await assertServerSwitchDoesNotRetainRemoval(usesInstanceID: true)
  }

  func testEndpointSwitchDoesNotRetainRemovalFromPreviousServer() async throws {
    try await assertServerSwitchDoesNotRetainRemoval(usesInstanceID: false)
  }

  func testSameServerReauthenticationDoesNotRetainNewerState() async throws {
    try await assertServerSwitchDoesNotRetainNewerState(
      usesInstanceID: true,
      changesServer: false
    )
  }

  func testSameServerReauthenticationDoesNotRetainRemoval() async throws {
    try await assertServerSwitchDoesNotRetainRemoval(
      usesInstanceID: true,
      changesServer: false
    )
  }

  func testReconnectRejectsReplacementAuthenticationSession() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(temperatureStates(value: 21), statusCode: 200)
      ]
    )
    let credentials = fixture.credentials()
    try await session.install(credentials)
    let firstConnection = refreshAuthenticatedConnection()
    let secondConnection = refreshAuthenticatedConnection()
    let sleeper = RecordingSubscriptionSleeper(blocks: true)
    let source = HomeAssistantStateStream(
      session: session,
      connector: TemperatureSubscriptionConnector(
        connections: [firstConnection, secondConnection]
      ),
      retryDelays: [.zero],
      sleep: sleeper.sleep
    )
    let probe = AsyncThrowingStreamTestProbe(await source.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    await fulfillment(of: [firstConnection.blockedReceiveStarted], timeout: 1)
    firstConnection.fail(with: URLError(.networkConnectionLost))
    await fulfillment(of: [probe.received(at: 1), sleeper.started], timeout: 1)

    try await session.install(credentials)
    sleeper.resume()
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    do {
      _ = try probe.value(at: 2)
      XCTFail("Expected the replacement authentication session to stop the old stream.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected authentication replacement error: \(error)")
    }
  }

  func testActiveObservationRejectsSnapshotAfterServerSwitch() async throws {
    let fixture = SessionFixture()
    let loader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let now = fixture.now
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { now }
      ),
      loader: loader,
      now: { now }
    )
    let credentials = fixture.credentials()
    try await session.install(credentials)
    let connection = refreshAuthenticatedConnection()
    let source = HomeAssistantStateStream(
      session: session,
      connector: TemperatureSubscriptionConnector(connections: [connection]),
      retryDelays: []
    )
    let probe = AsyncThrowingStreamTestProbe(await source.stateUpdates())
    await fulfillment(of: [loader.started], timeout: 1)

    try await session.install(
      switchedCredentials(from: credentials, usesInstanceID: true)
    )
    loader.succeed(with: temperatureStates(value: 20), statusCode: 200)
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    do {
      _ = try probe.value(at: 0)
      XCTFail("Expected the superseded server snapshot to be rejected.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected server-switch error: \(error)")
    }
  }

  private func assertServerSwitchDoesNotRetainNewerState(
    usesInstanceID: Bool,
    changesServer: Bool = true
  ) async throws {
    let setup = try await switchSetup(usesInstanceID: usesInstanceID)
    let firstProbe = AsyncThrowingStreamTestProbe(await setup.source.stateUpdates())
    await fulfillment(of: [firstProbe.received(at: 0)], timeout: 1)
    await fulfillment(of: [setup.firstConnection.blockedReceiveStarted], timeout: 1)
    setup.firstConnection.succeed(
      with: stateChangedEvent(entityID: "climate.bedroom", value: 25)
    )
    await fulfillment(of: [firstProbe.received(at: 1)], timeout: 1)
    await firstProbe.cancel()

    try await setup.session.install(
      changesServer
        ? switchedCredentials(from: setup.credentials, usesInstanceID: usesInstanceID)
        : setup.credentials
    )
    let secondProbe = AsyncThrowingStreamTestProbe(await setup.source.stateUpdates())
    await fulfillment(of: [secondProbe.received(at: 0)], timeout: 1)

    let state = try XCTUnwrap(try secondProbe.value(at: 0).states.first)
    let reading = try XCTUnwrap(
      state.temperatureReading(unit: "°C", metadata: nil)
    )
    XCTAssertEqual(reading.value, 20)
    setup.secondConnection.cancel()
  }

  private func assertServerSwitchDoesNotRetainRemoval(
    usesInstanceID: Bool,
    changesServer: Bool = true
  ) async throws {
    let setup = try await switchSetup(usesInstanceID: usesInstanceID)
    let firstProbe = AsyncThrowingStreamTestProbe(await setup.source.stateUpdates())
    await fulfillment(of: [firstProbe.received(at: 0)], timeout: 1)
    await fulfillment(of: [setup.firstConnection.blockedReceiveStarted], timeout: 1)
    setup.firstConnection.succeed(
      with: stateRemovedEvent(
        entityID: "climate.bedroom",
        oldLastUpdated: "2026-07-27T01:03:04Z"
      )
    )
    await fulfillment(of: [firstProbe.received(at: 1)], timeout: 1)
    await firstProbe.cancel()

    try await setup.session.install(
      changesServer
        ? switchedCredentials(from: setup.credentials, usesInstanceID: usesInstanceID)
        : setup.credentials
    )
    let secondProbe = AsyncThrowingStreamTestProbe(await setup.source.stateUpdates())
    await fulfillment(of: [secondProbe.received(at: 0)], timeout: 1)

    XCTAssertEqual(try secondProbe.value(at: 0).states.count, 1)
    setup.secondConnection.cancel()
  }
}

private struct StateRefreshSetup {
  let hub: HomeAssistantStateHub
  let probe: AsyncThrowingStreamTestProbe<HomeAssistantStateUpdate>
  let firstConnection: TemperatureSubscriptionConnection
  let secondConnection: TemperatureSubscriptionConnection
}

private struct StateSwitchSetup {
  let session: HomeAssistantSession
  let credentials: HomeAssistantCredentials
  let source: HomeAssistantStateStream
  let firstConnection: TemperatureSubscriptionConnection
  let secondConnection: TemperatureSubscriptionConnection
}

private func refreshSetup() async throws -> StateRefreshSetup {
  let fixture = SessionFixture()
  let session = fixture.makeSession(
    apiResponses: [
      .success(temperatureStates(value: 21), statusCode: 200),
      .success(temperatureStates(value: 20), statusCode: 200),
    ]
  )
  try await session.install(fixture.credentials())
  let firstConnection = refreshAuthenticatedConnection()
  let secondConnection = refreshAuthenticatedConnection()
  let source = HomeAssistantStateStream(
    session: session,
    connector: TemperatureSubscriptionConnector(
      connections: [firstConnection, secondConnection]
    ),
    retryDelays: []
  )
  let hub = HomeAssistantStateHub(source: source)
  let probe = AsyncThrowingStreamTestProbe(await hub.stateUpdates())
  return StateRefreshSetup(
    hub: hub,
    probe: probe,
    firstConnection: firstConnection,
    secondConnection: secondConnection
  )
}

private func switchSetup(usesInstanceID: Bool) async throws -> StateSwitchSetup {
  let fixture = SessionFixture()
  let session = fixture.makeSession(
    apiResponses: [
      .success(temperatureStates(value: 21), statusCode: 200),
      .success(temperatureStates(value: 20), statusCode: 200),
    ]
  )
  let fixtureCredentials = fixture.credentials()
  let credentials =
    usesInstanceID
    ? fixtureCredentials
    : credentialsWithoutInstanceID(from: fixtureCredentials)
  try await session.install(credentials)
  let firstConnection = refreshAuthenticatedConnection()
  let secondConnection = refreshAuthenticatedConnection()
  let source = HomeAssistantStateStream(
    session: session,
    connector: TemperatureSubscriptionConnector(
      connections: [firstConnection, secondConnection]
    ),
    retryDelays: []
  )
  return StateSwitchSetup(
    session: session,
    credentials: credentials,
    source: source,
    firstConnection: firstConnection,
    secondConnection: secondConnection
  )
}

private func switchedCredentials(
  from credentials: HomeAssistantCredentials,
  usesInstanceID: Bool
) -> HomeAssistantCredentials {
  let internalURL =
    usesInstanceID ? credentials.internalURL : URL(string: "http://other.local:8123")
  let externalURL =
    usesInstanceID ? credentials.externalURL : URL(string: "https://other.example")
  return HomeAssistantCredentials(
    instanceID: usesInstanceID ? "other-instance" : nil,
    instanceName: "Other Home",
    internalURL: internalURL,
    externalURL: externalURL,
    lastSuccessfulURL: internalURL ?? credentials.lastSuccessfulURL,
    accessToken: credentials.accessToken,
    refreshToken: credentials.refreshToken,
    tokenType: credentials.tokenType,
    accessTokenExpiresAt: credentials.accessTokenExpiresAt,
    clientID: credentials.clientID
  )
}

private func credentialsWithoutInstanceID(
  from credentials: HomeAssistantCredentials
) -> HomeAssistantCredentials {
  HomeAssistantCredentials(
    instanceID: nil,
    instanceName: credentials.instanceName,
    internalURL: credentials.internalURL,
    externalURL: credentials.externalURL,
    lastSuccessfulURL: credentials.lastSuccessfulURL,
    accessToken: credentials.accessToken,
    refreshToken: credentials.refreshToken,
    tokenType: credentials.tokenType,
    accessTokenExpiresAt: credentials.accessTokenExpiresAt,
    clientID: credentials.clientID
  )
}

private func refreshAuthenticatedConnection() -> TemperatureSubscriptionConnection {
  TemperatureSubscriptionConnection(
    messages: [
      .success(#"{"type":"auth_required"}"#),
      .success(#"{"type":"auth_ok"}"#),
      .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
    ]
  )
}

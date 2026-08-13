import Foundation
import XCTest

@testable import Bruce

extension HomeAssistantConnectionSupervisorTests {
  func testManualRefreshPublishesRefreshingBeforeReplacementLive() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection()
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [first, replacement])
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)

    let didRefresh = await supervisor.refresh()
    XCTAssertTrue(didRefresh)
    await fulfillment(of: [probe.received(at: 2)], timeout: 5)
    let refreshing = try probe.value(at: 1)
    await probe.cancel()

    XCTAssertEqual(refreshing.phase, .refreshing)
    XCTAssertEqual(temperature(from: refreshing), 21)
  }

  func testLastConsumerStopsTransportAndSupervisor() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection()
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection])
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)

    await probe.cancel()
    await fulfillment(of: [connection.cancelled], timeout: 5)
    await supervisor.stop()

    let stoppedState = await supervisor.state
    let credentialTask = await supervisor.credentialTask
    XCTAssertEqual(stoppedState, .stopped)
    XCTAssertNil(credentialTask)
  }

  func testReadinessOnlyConsumerStopsTransportAfterBecomingLive() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection()
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection])
    )

    try await supervisor.requireFreshLiveData()
    await fulfillment(of: [connection.cancelled], timeout: 5)

    let stoppedState = await supervisor.state
    let credentialTask = await supervisor.credentialTask
    XCTAssertEqual(stoppedState, .stopped)
    XCTAssertNil(credentialTask)
  }

  func testCleanServerCloseReconnectsWithoutReplacingConsumer() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)

    first.fail(with: CleanWebSocketClose())
    await fulfillment(of: [probe.received(at: 2)], timeout: 5)
    let reconnecting = try probe.value(at: 1)
    let recovered = try probe.value(at: 2)
    await probe.cancel()

    XCTAssertEqual(reconnecting.phase, .reconnecting)
    XCTAssertEqual(temperature(from: reconnecting), 21)
    XCTAssertEqual(recovered.phase, .live)
    XCTAssertEqual(temperature(from: recovered), 23)
    XCTAssertEqual(connector.connectionCount, 2)
  }

  func testBlockedAuthenticationExpiresAndEntersRecovery() async throws {
    let fixture = SupervisorFixture(snapshotValues: [])
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection(blocksAuthentication: true)
    let replacement = ScriptedHomeAssistantConnection()
    let clock = ControlledConnectionClock()
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection, replacement]),
      clock: clock.connectionClock
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [connection.authenticationStarted], timeout: 5)
    let deadline = clock.expectSleep(.seconds(30))
    await fulfillment(of: [deadline], timeout: 5)

    clock.resume(.seconds(30), advancingBy: 30)
    await fulfillment(of: [connection.cancelled, probe.received(at: 0)], timeout: 5)
    let recovery = try probe.value(at: 0)
    await probe.cancel()

    XCTAssertEqual(recovery.phase, .reconnecting)
  }

  func testInitialProtocolFailurePublishesUnavailable() async throws {
    let fixture = SupervisorFixture(snapshotValues: [])
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection(authenticationResponse: "unexpected")
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection])
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)
    let unavailable = try probe.value(at: 0)
    let state = await supervisor.state
    await probe.cancel()

    XCTAssertEqual(unavailable.phase, .unavailable)
    XCTAssertEqual(unavailable.failure, .unknown)
    XCTAssertEqual(state, .requiresUserAction)
  }

  func testAuthenticationRejectionRefreshesOnceAndRecovers() async throws {
    let fixture = SupervisorFixture(snapshotValues: [24])
    fixture.authenticationLoader.results = [.success(refreshedToken(), statusCode: 200)]
    try await fixture.install()
    let rejected = ScriptedHomeAssistantConnection(authenticationResponse: "auth_invalid")
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [rejected, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())

    await fulfillment(of: [probe.received(at: 0)], timeout: 5)
    let live = try probe.value(at: 0)
    await probe.cancel()

    XCTAssertEqual(live.phase, .live)
    XCTAssertEqual(temperature(from: live), 24)
    XCTAssertEqual(fixture.authenticationLoader.requests.count, 1)
    XCTAssertEqual(connector.connectionCount, 2)
  }

  func testRefreshedTokenRejectionPublishesAuthenticationUnavailable() async throws {
    let fixture = SupervisorFixture(snapshotValues: [])
    fixture.authenticationLoader.results = [.success(refreshedToken(), statusCode: 200)]
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection(authenticationResponse: "auth_invalid")
    let refreshed = ScriptedHomeAssistantConnection(authenticationResponse: "auth_invalid")
    let connector = ScriptedHomeAssistantConnector(connections: [first, refreshed])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())

    await fulfillment(of: [probe.received(at: 1)], timeout: 5)
    var unavailable = try probe.value(at: 1)
    if unavailable.phase != .unavailable {
      await fulfillment(of: [probe.received(at: 2)], timeout: 5)
      unavailable = try probe.value(at: 2)
    }
    let state = await supervisor.state
    let credentials = await fixture.session.currentCredentials()
    await probe.cancel()

    XCTAssertEqual(unavailable.phase, .unavailable)
    XCTAssertEqual(unavailable.failure, .authentication)
    XCTAssertEqual(state, .requiresUserAction)
    XCTAssertNil(credentials)
    XCTAssertEqual(fixture.authenticationLoader.requests.count, 1)
    XCTAssertEqual(connector.connectionCount, 2)
  }

  func testRefreshedTokenRejectionTriesAlternateRouteBeforeRejectingCredentials() async throws {
    let externalURL = try XCTUnwrap(URL(string: "https://home.example"))
    let fixture = SupervisorFixture(snapshotValues: [24], externalURL: externalURL)
    fixture.authenticationLoader.results = [.success(refreshedToken(), statusCode: 200)]
    try await fixture.install()
    let preferred = ScriptedHomeAssistantConnection(authenticationResponse: "auth_invalid")
    let refreshedPreferred = ScriptedHomeAssistantConnection(
      authenticationResponse: "auth_invalid"
    )
    let alternate = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(
      connections: [preferred, refreshedPreferred, alternate]
    )
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())

    await fulfillment(of: [probe.received(at: 1)], timeout: 5)

    XCTAssertEqual(try probe.value(at: 1).phase, .live)
    XCTAssertEqual(connector.connectionCount, 3)
    XCTAssertEqual(Set(connector.connectedURLs.compactMap(\.host)), ["home.local", "home.example"])
    let remainingCredentials = await fixture.session.currentCredentials()
    XCTAssertNotNil(remainingCredentials)
    XCTAssertFalse(fixture.authenticationLoader.requests.isEmpty)
    await probe.cancel()
  }

  func testOfflineRejectedTokenRefreshPreservesCredentialsAndRetriesRefresh() async throws {
    let fixture = SupervisorFixture(snapshotValues: [25])
    fixture.authenticationLoader.results = [
      .failure(URLError(.notConnectedToInternet)),
      .success(refreshedToken(), statusCode: 200),
    ]
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection(authenticationResponse: "auth_invalid")
    let second = ScriptedHomeAssistantConnection(authenticationResponse: "auth_invalid")
    let recovered = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, second, recovered])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())

    await fulfillment(of: [probe.received(at: 1)], timeout: 5)
    let live = try probe.value(at: 1)
    let credentials = await fixture.session.currentCredentials()
    await probe.cancel()

    XCTAssertEqual(live.phase, .live)
    XCTAssertEqual(temperature(from: live), 25)
    XCTAssertNotNil(credentials)
    XCTAssertEqual(fixture.authenticationLoader.requests.count, 2)
    XCTAssertEqual(connector.connectionCount, 3)
  }

  func testSnapshotRejectionAfterForcedRefreshBecomesAuthenticationTerminal() async throws {
    let fixture = SupervisorFixture(snapshotValues: [])
    fixture.apiLoader.results = [
      .success(Data(), statusCode: 401),
      .success(Data(), statusCode: 401),
    ]
    fixture.authenticationLoader.results = [.success(refreshedToken(), statusCode: 200)]
    try await fixture.install()
    let connector = ScriptedHomeAssistantConnector(
      connections: [ScriptedHomeAssistantConnection()]
    )
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())

    await fulfillment(of: [probe.received(at: 1)], timeout: 5)
    let unavailable = try probe.value(at: 1)

    XCTAssertEqual(unavailable.phase, .unavailable)
    XCTAssertEqual(unavailable.failure, .authentication)
    let state = await supervisor.state
    let credentials = await fixture.session.currentCredentials()
    XCTAssertEqual(state, .requiresUserAction)
    XCTAssertNil(credentials)
    XCTAssertEqual(connector.connectionCount, 1)
    XCTAssertFalse(fixture.authenticationLoader.requests.isEmpty)
    await probe.cancel()
  }

  func testPreSnapshotEventsCoalesceByEntity() async throws {
    let attempt = HomeAssistantConnectionAttempt(
      id: UUID(),
      authenticationSessionEpoch: 1,
      routeCategory: "preferred",
      now: { 0 }
    )
    for value in 1...100 {
      try await attempt.receive(
        Data(stateChangedEvent(entityID: "climate.bedroom", value: Double(value)).utf8)
      )
    }

    let events = try await attempt.beginPublishingEvents()
    await attempt.finish()

    XCTAssertEqual(events.buffered.count, 1)
    XCTAssertTrue(String(data: events.buffered[0], encoding: .utf8)?.contains("100") == true)
  }

}

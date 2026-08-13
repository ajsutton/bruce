import Foundation
import XCTest

@testable import Bruce

final class ConnectionSupervisorConcurrencyTests: XCTestCase {
  func testRepeatedWakeDuringReplacementCoalescesIntoOneAttempt() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection(blocksAuthentication: true)
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    await supervisor.receiveWakeHint()
    await fulfillment(of: [replacement.authenticationStarted], timeout: 1)
    await supervisor.receiveWakeHint()

    XCTAssertFalse(replacement.isCancelled)
    XCTAssertEqual(connector.connectionCount, 2)

    await supervisor.setApplicationActive(false)
    await probe.cancel()
  }

  func testRepeatedPathHintsDuringBackoffStartOneReplacement() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let clock = ControlledConnectionClock()
    let supervisor = HomeAssistantConnectionSupervisor(
      session: fixture.session,
      connector: connector,
      credentialEvents: fixture.credentialEvents,
      retryPolicy: HomeAssistantConnectionRetryPolicy(
        initialWindow: 30,
        maximumWindow: 30,
        randomUnit: { 1 }
      ),
      clock: clock.connectionClock
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let backoffStarted = clock.expectSleep(.seconds(30))

    first.fail(with: URLError(.networkConnectionLost))
    await fulfillment(of: [backoffStarted], timeout: 1)
    await supervisor.receivePathHint()
    await supervisor.receivePathHint()
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    XCTAssertEqual(connector.connectionCount, 2)
    XCTAssertEqual(try probe.value(at: 2).phase, .live)
    await probe.cancel()
  }

  func testReplacementWhileRecoveryIsSuspendedCannotPublishStaleFailure() async throws {
    let now = MutableConnectionDate(Date(timeIntervalSince1970: 20_000))
    let credentialEvents = HomeAssistantCredentialEvents()
    let credentialStore = InMemoryHomeAssistantCredentialStore()
    let authenticationLoader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let apiLoader = QueueHomeAssistantLoader()
    apiLoader.results = [.success(temperatureStates(value: 24), statusCode: 200)]
    let session = HomeAssistantSession(
      credentialStore: credentialStore,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: authenticationLoader,
        now: now.value
      ),
      loader: apiLoader,
      now: now.value,
      credentialEvents: credentialEvents
    )
    try await session.install(credentials(expiresAt: now.value().addingTimeInterval(3_600)))
    let stale = ScriptedHomeAssistantConnection(
      authenticationResponse: "unexpected",
      blocksAuthentication: true
    )
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [stale, replacement])
    let supervisor = HomeAssistantConnectionSupervisor(
      session: session,
      connector: connector,
      credentialEvents: credentialEvents,
      retryPolicy: HomeAssistantConnectionRetryPolicy(
        initialWindow: 0,
        maximumWindow: 0,
        randomUnit: { 0 }
      )
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [stale.authenticationStarted], timeout: 1)
    now.set(Date(timeIntervalSince1970: 30_000))
    stale.completeAuthentication()
    await fulfillment(of: [authenticationLoader.started], timeout: 1)

    await supervisor.receiveWakeHint()
    now.set(Date(timeIntervalSince1970: 20_000))
    authenticationLoader.succeed(with: refreshedToken(), statusCode: 200)
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)

    let reconnectingUpdate = try probe.value(at: 0)
    let liveUpdate = try probe.value(at: 1)
    let state = await supervisor.state
    XCTAssertEqual(reconnectingUpdate.phase, .reconnecting)
    XCTAssertEqual(liveUpdate.phase, .live)
    XCTAssertEqual(state, .live)
    XCTAssertEqual(connector.connectionCount, 2)
    await probe.cancel()
  }

  func testOlderCredentialSnapshotsCannotReplaceNewerIdentity() async {
    let fixture = SupervisorFixture(snapshotValues: [])
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [])
    )
    let newest = HomeAssistantCredentialSnapshot(
      authenticationSessionEpoch: 4,
      persistenceGeneration: 9,
      availability: .ready
    )
    await supervisor.receiveCredentialSnapshot(newest)

    await supervisor.receiveCredentialSnapshot(
      HomeAssistantCredentialSnapshot(
        authenticationSessionEpoch: 3,
        persistenceGeneration: 20,
        availability: .rejected
      ))
    await supervisor.receiveCredentialSnapshot(
      HomeAssistantCredentialSnapshot(
        authenticationSessionEpoch: 4,
        persistenceGeneration: 8,
        availability: .missing
      ))

    let installed = await supervisor.credentialSnapshot
    XCTAssertEqual(installed, newest)
  }

  func testRapidActivityInversionCancelsAttemptWithoutLatePublication() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection(blocksAuthentication: true)
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    await supervisor.setApplicationActive(false)
    await supervisor.setApplicationActive(true)
    await fulfillment(of: [replacement.authenticationStarted], timeout: 1)
    await supervisor.setApplicationActive(false)
    await fulfillment(of: [replacement.cancelled], timeout: 1)
    replacement.completeAuthentication()

    let state = await supervisor.state
    let update = await supervisor.latestUpdate
    XCTAssertEqual(state, .suspended)
    XCTAssertEqual(update?.phase, .reconnecting)
    XCTAssertEqual(connector.connectionCount, 2)
    await probe.cancel()
  }

  func testLateHeartbeatReplacesSocketWithoutSendingPing() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let clock = ControlledConnectionClock()
    let heartbeatScheduled = clock.expectSleep(.seconds(60))
    let supervisor = fixture.makeSupervisor(
      connector: connector,
      clock: clock.connectionClock
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0), heartbeatScheduled], timeout: 1)

    clock.resume(.seconds(60), advancingBy: 100)
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    XCTAssertEqual(first.pingCount, 0)
    XCTAssertTrue(first.isCancelled)
    XCTAssertEqual(connector.connectionCount, 2)
    XCTAssertEqual(try probe.value(at: 2).phase, .live)
    await probe.cancel()
  }

  private func credentials(expiresAt: Date) -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(string: "http://home.local:8123")
        ?? URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: expiresAt,
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }

  private func refreshedToken() -> Data {
    Data(
      """
      {
        "access_token": "refreshed-access",
        "token_type": "Bearer",
        "expires_in": 1800
      }
      """.utf8
    )
  }
}

private final class MutableConnectionDate: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: Date

  init(_ value: Date) {
    storedValue = value
  }

  func value() -> Date {
    lock.withLock { storedValue }
  }

  func set(_ value: Date) {
    lock.withLock { storedValue = value }
  }
}

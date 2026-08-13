import Foundation
import XCTest

@testable import Bruce

final class SupervisorPersistenceTests: XCTestCase {
  func testNetworkAbsenceRetriesAtTheCapUntilAReplacementBecomesLive() async throws {
    let fixture = SupervisorFixture(snapshotValues: [24])
    try await fixture.install()
    let unavailable = (0..<3).map { _ in
      ScriptedHomeAssistantConnection(
        initialReceiveError: URLError(.notConnectedToInternet)
      )
    }
    let recovered = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: unavailable + [recovered])
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
      clock: clock.connectionClock,
      phaseDeadline: .seconds(90)
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())

    for _ in unavailable {
      let retryScheduled = clock.expectSleep(.seconds(30))
      await fulfillment(of: [retryScheduled], timeout: 1)
      clock.resume(.seconds(30), advancingBy: 30)
    }
    await fulfillment(of: [recovered.authenticationStarted, probe.received(at: 3)], timeout: 1)

    XCTAssertEqual(try probe.value(at: 3).phase, .live)
    XCTAssertEqual(connector.connectionCount, 4)
    XCTAssertTrue(unavailable.allSatisfy { $0.subscriptionCount == 0 })
    XCTAssertEqual(recovered.subscriptionCount, 6)
    XCTAssertEqual(fixture.apiLoader.requests.count, 1)
    await probe.cancel()
  }

  func testRESTTokenRefreshDuringSnapshotKeepsAuthenticatedSocket() async throws {
    let now = MutableSupervisorDate(Date(timeIntervalSince1970: 20_000))
    let credentialEvents = HomeAssistantCredentialEvents()
    let store = InMemoryHomeAssistantCredentialStore()
    let refreshLoader = BlockingHomeAssistantLoader()
    let apiLoader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let session = HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: refreshLoader,
        now: now.value
      ),
      loader: apiLoader,
      now: now.value,
      credentialEvents: credentialEvents
    )
    try await session.install(credentials(expiresAt: now.value().addingTimeInterval(3_600)))
    let connection = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [connection])
    let supervisor = HomeAssistantConnectionSupervisor(
      session: session,
      connector: connector,
      credentialEvents: credentialEvents
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [apiLoader.started], timeout: 1)

    now.set(Date(timeIntervalSince1970: 30_000))
    let request = Task { try await session.authenticatedGET(path: "api/states") }
    await fulfillment(of: [refreshLoader.started], timeout: 1)
    refreshLoader.succeed(with: refreshedToken(), statusCode: 200)
    apiLoader.succeed(with: temperatureStates(value: 24), statusCode: 200)

    _ = try await request.value
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    XCTAssertEqual(try probe.value(at: 0).phase, .live)
    XCTAssertEqual(connector.connectionCount, 1)
    XCTAssertEqual(connection.subscriptionCount, 6)
    XCTAssertEqual(refreshLoader.requests.count, 1)
    XCTAssertEqual(apiLoader.requests.count, 2)
    await probe.cancel()
  }

  func testConcurrentRESTAndWebSocketAccessCoalesceTokenRefresh() async throws {
    let fixture = SessionFixture()
    let refreshLoader = BlockingHomeAssistantLoader()
    fixture.apiLoader.results = [.success(Data("states".utf8), statusCode: 200)]
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: refreshLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now }
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))

    async let rest = session.authenticatedGET(path: "api/states")
    async let socketAccesses = session.authenticatedWebSocketAccesses()
    await fulfillment(of: [refreshLoader.started], timeout: 1)
    refreshLoader.succeed(with: refreshedToken(), statusCode: 200)

    let (data, accesses) = try await (rest, socketAccesses)
    XCTAssertEqual(data, Data("states".utf8))
    XCTAssertEqual(accesses.first?.accessToken, "refreshed-access")
    XCTAssertEqual(refreshLoader.requests.count, 2)
    XCTAssertEqual(fixture.apiLoader.requests.count, 1)
  }

  private func credentials(expiresAt: Date) -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: nil,
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

private final class MutableSupervisorDate: @unchecked Sendable {
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

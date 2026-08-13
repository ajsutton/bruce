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
      await fulfillment(of: [retryScheduled], timeout: 5)
      clock.resume(.seconds(30), advancingBy: 30)
    }
    await fulfillment(of: [recovered.authenticationStarted, probe.received(at: 3)], timeout: 5)

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
    let apiLoader = OrderedBlockingHomeAssistantLoader(requestCount: 2)
    defer { apiLoader.cancelAll() }
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
    let supervisor = supervisor(
      session: session,
      connector: connector,
      credentialEvents: credentialEvents
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [apiLoader.started(at: 0)], timeout: 5)

    now.set(Date(timeIntervalSince1970: 30_000))
    let request = Task { try await session.authenticatedGET(path: "api/states") }
    await fulfillment(of: [refreshLoader.started], timeout: 5)
    refreshLoader.succeed(with: refreshedToken(), statusCode: 200)
    await fulfillment(of: [apiLoader.started(at: 1)], timeout: 5)
    apiLoader.complete(request: 1, data: temperatureStates(value: 24), statusCode: 200)

    _ = try await request.value
    apiLoader.complete(request: 0, data: temperatureStates(value: 24), statusCode: 200)
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)
    XCTAssertEqual(try probe.value(at: 0).phase, .live)
    XCTAssertEqual(connector.connectionCount, 1)
    XCTAssertEqual(connection.subscriptionCount, 6)
    XCTAssertEqual(refreshLoader.requests.count, 1)
    XCTAssertEqual(apiLoader.requests.count, 2)
    await probe.cancel()
  }

  func testRouteChangingRefreshDuringFallbackSnapshotKeepsAuthenticatedSocket() async throws {
    try await assertRouteChangingRefreshDuringFallbackSnapshot(
      successfulRefreshHost: "home.example"
    )
  }

  func testFallbackSnapshotSurvivesRefreshOnOriginalRoute() async throws {
    try await assertRouteChangingRefreshDuringFallbackSnapshot(
      successfulRefreshHost: "home.local"
    )
  }

  private func assertRouteChangingRefreshDuringFallbackSnapshot(
    successfulRefreshHost: String
  ) async throws {
    let now = MutableSupervisorDate(Date(timeIntervalSince1970: 20_000))
    let credentialEvents = HomeAssistantCredentialEvents()
    let refreshLoader = OrderedBlockingHomeAssistantLoader(requestCount: 2)
    let apiLoader = OrderedBlockingHomeAssistantLoader(requestCount: 3)
    defer {
      refreshLoader.cancelAll()
      apiLoader.cancelAll()
    }
    let session = HomeAssistantSession(
      credentialStore: InMemoryHomeAssistantCredentialStore(),
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: refreshLoader,
        now: now.value
      ),
      loader: apiLoader,
      now: now.value,
      credentialEvents: credentialEvents
    )
    let externalURL = URL(string: "https://home.example") ?? URL(fileURLWithPath: "/")
    let installed = credentials(
      expiresAt: now.value().addingTimeInterval(3_600),
      externalURL: externalURL
    )
    try await session.install(installed)
    let connection = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [connection])
    let supervisor = supervisor(
      session: session,
      connector: connector,
      credentialEvents: credentialEvents
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [apiLoader.started(at: 0)], timeout: 5)
    apiLoader.complete(request: 0, error: URLError(.notConnectedToInternet))
    await fulfillment(of: [apiLoader.started(at: 1)], timeout: 5)

    now.set(Date(timeIntervalSince1970: 30_000))
    let request = Task { try await session.authenticatedGET(path: "api/states") }
    await fulfillment(
      of: [refreshLoader.started(at: 0), refreshLoader.started(at: 1)],
      timeout: 5
    )
    try completeRefresh(refreshLoader, successfulHost: successfulRefreshHost)
    await fulfillment(of: [apiLoader.started(at: 2)], timeout: 5)
    apiLoader.complete(request: 2, data: temperatureStates(value: 24), statusCode: 200)

    _ = try await request.value
    apiLoader.complete(request: 1, data: temperatureStates(value: 24), statusCode: 200)
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)
    XCTAssertEqual(try probe.value(at: 0).phase, .live)
    XCTAssertEqual(connector.connectionCount, 1)
    await probe.cancel()
  }

  private func supervisor(
    session: HomeAssistantSession,
    connector: ScriptedHomeAssistantConnector,
    credentialEvents: HomeAssistantCredentialEvents
  ) -> HomeAssistantConnectionSupervisor {
    HomeAssistantConnectionSupervisor(
      session: session,
      connector: connector,
      credentialEvents: credentialEvents
    )
  }

  private func completeRefresh(
    _ loader: OrderedBlockingHomeAssistantLoader,
    successfulHost: String
  ) throws {
    let requests = loader.requests
    let successful = try XCTUnwrap(
      requests.firstIndex { $0.url?.host() == successfulHost }
    )
    let failed = try XCTUnwrap(requests.indices.first { $0 != successful })
    loader.complete(request: failed, error: URLError(.notConnectedToInternet))
    loader.complete(request: successful, data: refreshedToken(), statusCode: 200)
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
    await fulfillment(of: [refreshLoader.started], timeout: 5)
    refreshLoader.succeed(with: refreshedToken(), statusCode: 200)

    let (data, accesses) = try await (rest, socketAccesses)
    XCTAssertEqual(data, Data("states".utf8))
    XCTAssertEqual(accesses.first?.accessToken, "refreshed-access")
    XCTAssertEqual(refreshLoader.requests.count, 2)
    XCTAssertEqual(fixture.apiLoader.requests.count, 1)
  }

  private func credentials(
    expiresAt: Date,
    externalURL: URL? = nil
  ) -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: externalURL,
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

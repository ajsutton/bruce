import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantConnectionCoordinatorTests: XCTestCase {
  func testConnectAuthenticatesVerifiesAndSavesBothAddresses() async throws {
    let fixture = CoordinatorFixture()
    fixture.authenticationLoader.results = [.success(fixture.tokenResponse, statusCode: 200)]
    let loader = RacingHomeAssistantLoader(
      blockedHost: fixture.externalURL.host() ?? "",
      successfulData: fixture.statusResponse
    )
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: fixture.authenticationClient,
      loader: loader,
      now: { [now = fixture.now] in now }
    )
    let coordinator = fixture.makeCoordinator(session: session)

    let credentials = try await coordinator.connect(to: fixture.candidate)

    XCTAssertEqual(credentials.internalURL, fixture.internalURL)
    XCTAssertEqual(credentials.externalURL, fixture.externalURL)
    XCTAssertEqual(credentials.lastSuccessfulURL, fixture.internalURL)
    XCTAssertEqual(credentials.accessToken, "new-access")
    let storedCredentials = await fixture.store.value
    XCTAssertEqual(storedCredentials, credentials)
    XCTAssertEqual(fixture.browser.authenticationCount, 1)
    XCTAssertTrue(loader.wasBlockedRouteCancelled)
  }

  func testFailedVerificationPreservesExistingConnection() async throws {
    let fixture = CoordinatorFixture()
    let session = fixture.makeSession()
    let existing = fixture.existingCredentials()
    try await session.install(existing)
    fixture.authenticationLoader.results = [.success(fixture.tokenResponse, statusCode: 200)]
    fixture.apiLoader.results = Array(
      repeating: .success(Data("{}".utf8), statusCode: 200),
      count: 2
    )
    let coordinator = fixture.makeCoordinator(session: session)

    do {
      _ = try await coordinator.connect(to: fixture.candidate)
      XCTFail("Expected verification to fail.")
    } catch HomeAssistantAPIError.incompatibleServer {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertEqual(currentCredentials, existing)
    XCTAssertEqual(storedCredentials, existing)
  }

  func testConnectReturnsExternalRouteWhenInternalVerificationCannotConnect() async throws {
    let fixture = CoordinatorFixture()
    fixture.authenticationLoader.results = [.success(fixture.tokenResponse, statusCode: 200)]
    let loader = HostRoutingHomeAssistantLoader(
      failingHost: fixture.internalURL.host() ?? "",
      successfulData: fixture.statusResponse
    )
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: fixture.authenticationClient,
      loader: loader,
      now: { [now = fixture.now] in now }
    )
    let coordinator = fixture.makeCoordinator(session: session)

    let credentials = try await coordinator.connect(to: fixture.candidate)

    XCTAssertEqual(credentials.lastSuccessfulURL, fixture.externalURL)
    let storedCredentials = await fixture.store.value
    XCTAssertEqual(storedCredentials?.lastSuccessfulURL, fixture.externalURL)
  }

  func testConnectionCheckUsesExternalRouteWithoutWaitingForInternalRoute() async throws {
    let fixture = CoordinatorFixture()
    let session = fixture.makeSession()
    let existingCredentials = fixture.existingCredentials()
    try await session.install(existingCredentials)
    let loader = RacingHomeAssistantLoader(
      blockedHost: existingCredentials.internalURL?.host() ?? "",
      successfulData: fixture.statusResponse
    )
    let racingSession = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: fixture.authenticationClient,
      loader: loader,
      now: { [now = fixture.now] in now }
    )
    _ = try await racingSession.restore()
    let coordinator = fixture.makeCoordinator(session: racingSession)

    let credentials = try await coordinator.testConnection()

    XCTAssertEqual(credentials.lastSuccessfulURL, existingCredentials.externalURL)
    XCTAssertTrue(loader.wasBlockedRouteCancelled)
    XCTAssertEqual(Set(loader.requestedHosts), Set(["existing.local", "existing.example"]))
  }

  func testNewConnectionUsesExternalRouteWithoutWaitingForInternalRoute() async throws {
    let fixture = CoordinatorFixture()
    fixture.authenticationLoader.results = [.success(fixture.tokenResponse, statusCode: 200)]
    let loader = RacingHomeAssistantLoader(
      blockedHost: fixture.internalURL.host() ?? "",
      successfulData: fixture.statusResponse
    )
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: fixture.authenticationClient,
      loader: loader,
      now: { [now = fixture.now] in now }
    )
    let coordinator = fixture.makeCoordinator(session: session)

    let credentials = try await coordinator.connect(to: fixture.candidate)

    XCTAssertEqual(credentials.lastSuccessfulURL, fixture.externalURL)
    XCTAssertTrue(loader.wasBlockedRouteCancelled)
    XCTAssertEqual(Set(loader.requestedHosts), Set(["new.local", "new.example"]))
  }

  func testBrowserCancellationDoesNotChangeExistingConnection() async throws {
    let fixture = CoordinatorFixture()
    let session = fixture.makeSession()
    let existing = fixture.existingCredentials()
    try await session.install(existing)
    fixture.browser.error = CancellationError()
    let coordinator = fixture.makeCoordinator(session: session)

    do {
      _ = try await coordinator.connect(to: fixture.candidate)
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertEqual(currentCredentials, existing)
    XCTAssertEqual(storedCredentials, existing)
    XCTAssertTrue(fixture.authenticationLoader.requests.isEmpty)
  }

  func testDisconnectDeletesCredentialsWhenRevocationFails() async throws {
    let fixture = CoordinatorFixture()
    let session = fixture.makeSession()
    try await session.install(fixture.existingCredentials())
    fixture.authenticationLoader.results = [
      .failure(URLError(.notConnectedToInternet)),
      .failure(URLError(.notConnectedToInternet)),
    ]
    let coordinator = fixture.makeCoordinator(session: session)

    try await coordinator.disconnect()

    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertNil(currentCredentials)
    XCTAssertNil(storedCredentials)
    XCTAssertEqual(fixture.authenticationLoader.requests.count, 2)
  }

  func testCancelledDisconnectDoesNotDeleteCredentialsAfterLateRevocation() async throws {
    let fixture = CoordinatorFixture()
    let session = fixture.makeSession()
    let existing = fixture.existingCredentials()
    try await session.install(existing)
    let revocationLoader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let coordinator = HomeAssistantConnectionCoordinator(
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: revocationLoader,
        now: { [now = fixture.now] in now }
      ),
      browser: fixture.browser,
      session: session
    )
    let disconnect = Task {
      try await coordinator.disconnect()
    }
    await fulfillment(of: [revocationLoader.started], timeout: 1)

    disconnect.cancel()
    revocationLoader.succeed(with: Data(), statusCode: 200)

    do {
      try await disconnect.value
      XCTFail("Expected disconnect cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertEqual(currentCredentials, existing)
    XCTAssertEqual(storedCredentials, existing)
  }
}

private final class HostRoutingHomeAssistantLoader:
  HomeAssistantHTTPDataLoading, @unchecked Sendable
{
  private let failingHost: String
  private let successfulData: Data

  init(failingHost: String, successfulData: Data) {
    self.failingHost = failingHost
    self.successfulData = successfulData
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    guard request.url?.host() != failingHost else {
      throw URLError(.cannotConnectToHost)
    }
    let responseURL = request.url ?? URL(fileURLWithPath: "/")
    guard
      let response = HTTPURLResponse(
        url: responseURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return (successfulData, response)
  }
}

@MainActor
private final class CoordinatorFixture {
  let internalURL = URL(string: "http://new.local:8123") ?? URL(fileURLWithPath: "/")
  let externalURL = URL(string: "https://new.example") ?? URL(fileURLWithPath: "/")
  let store = InMemoryHomeAssistantCredentialStore()
  let authenticationLoader = QueueHomeAssistantLoader()
  let apiLoader = QueueHomeAssistantLoader()
  let browser = StubHomeAssistantWebAuthenticator()
  let now = Date(timeIntervalSince1970: 20_000)

  var tokenResponse: Data {
    Data(
      """
      {
        "access_token": "new-access",
        "refresh_token": "new-refresh",
        "token_type": "Bearer",
        "expires_in": 1800
      }
      """.utf8
    )
  }

  var statusResponse: Data {
    Data(#"{"message":"API running."}"#.utf8)
  }

  var candidate: HomeAssistantConnectionCandidate {
    HomeAssistantConnectionCandidate(
      instanceID: "new-instance",
      name: "New Home",
      internalURL: internalURL,
      externalURL: externalURL,
      activeURL: internalURL,
      source: .discovered
    )
  }

  func makeSession() -> HomeAssistantSession {
    HomeAssistantSession(
      credentialStore: store,
      authenticationClient: authenticationClient,
      loader: apiLoader,
      now: { [now] in now }
    )
  }

  func makeCoordinator(
    session: HomeAssistantSession? = nil
  ) -> HomeAssistantConnectionCoordinator {
    HomeAssistantConnectionCoordinator(
      authenticationClient: authenticationClient,
      browser: browser,
      session: session ?? makeSession()
    )
  }

  func existingCredentials() -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "existing",
      instanceName: "Existing Home",
      internalURL: URL(string: "http://existing.local:8123"),
      externalURL: URL(string: "https://existing.example"),
      lastSuccessfulURL: URL(string: "https://existing.example")
        ?? URL(fileURLWithPath: "/"),
      accessToken: "existing-access",
      refreshToken: "existing-refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: now.addingTimeInterval(3_600),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }

  var authenticationClient: HomeAssistantAuthenticationClient {
    HomeAssistantAuthenticationClient(
      loader: authenticationLoader,
      now: { [now] in now },
      stateGenerator: { "expected-state" }
    )
  }
}

@MainActor
private final class StubHomeAssistantWebAuthenticator: HomeAssistantWebAuthenticating {
  var error: (any Error)?
  private(set) var authenticationCount = 0

  func authenticate(at url: URL) async throws -> URL {
    authenticationCount += 1
    if let error {
      throw error
    }
    guard
      var components = URLComponents(
        url: HomeAssistantOAuthConfiguration.release.redirectURI,
        resolvingAgainstBaseURL: false
      )
    else {
      throw HomeAssistantAuthenticationError.invalidCallback
    }
    components.queryItems = [
      URLQueryItem(name: "code", value: "authorization-code"),
      URLQueryItem(name: "state", value: "expected-state"),
    ]
    guard let callback = components.url else {
      throw HomeAssistantAuthenticationError.invalidCallback
    }
    return callback
  }

  func cancel() {}
}

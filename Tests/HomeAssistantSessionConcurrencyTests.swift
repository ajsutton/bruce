import XCTest

@testable import Bruce

final class HomeAssistantSessionConcurrencyTests: XCTestCase {
  func testConcurrentReadsCoalesceAnExpiredTokenRefresh() async throws {
    let fixture = SessionFixture()
    let refreshLoader = BlockingHomeAssistantLoader()
    let session = makeSession(fixture: fixture, refreshLoader: refreshLoader)
    fixture.apiLoader.results = [
      .success(Data("first".utf8), statusCode: 200),
      .success(Data("second".utf8), statusCode: 200),
    ]
    try await session.install(fixture.credentials(expiresAt: fixture.past))

    async let first = session.authenticatedGET(path: "api/first")
    async let second = session.authenticatedGET(path: "api/second")
    await fulfillment(of: [refreshLoader.started], timeout: 1)
    refreshLoader.succeed(with: refreshedTokenResponse, statusCode: 200)

    let responses = try await [first, second]

    XCTAssertEqual(Set(responses), Set([Data("first".utf8), Data("second".utf8)]))
    XCTAssertEqual(refreshLoader.requests.count, 2)
  }

  func testConcurrentReadsShareRejectedRefreshOutcome() async throws {
    let fixture = SessionFixture()
    let refreshLoader = BlockingHomeAssistantLoader()
    let session = makeSession(fixture: fixture, refreshLoader: refreshLoader)
    try await session.install(fixture.credentials(expiresAt: fixture.past))

    async let first = Self.reauthenticationResult(from: session, path: "api/first")
    async let second = Self.reauthenticationResult(from: session, path: "api/second")
    await fulfillment(of: [refreshLoader.started], timeout: 1)
    refreshLoader.succeed(with: Data(#"{"error":"invalid_grant"}"#.utf8), statusCode: 400)

    let results = await [first, second]

    XCTAssertEqual(results, [true, true])
    XCTAssertEqual(refreshLoader.requests.count, 2)
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertNil(currentCredentials)
    XCTAssertNil(storedCredentials)
  }

  func testReadAfterRejectedRefreshRequiresReauthentication() async throws {
    let fixture = SessionFixture()
    let refreshLoader = BlockingHomeAssistantLoader()
    let session = makeSession(fixture: fixture, refreshLoader: refreshLoader)
    try await session.install(fixture.credentials(expiresAt: fixture.past))
    async let rejected = Self.reauthenticationResult(from: session, path: "api/first")
    await fulfillment(of: [refreshLoader.started], timeout: 1)
    refreshLoader.succeed(with: Data(#"{"error":"invalid_grant"}"#.utf8), statusCode: 400)
    let rejectedResult = await rejected
    XCTAssertTrue(rejectedResult)

    let laterRead = await Self.reauthenticationResult(from: session, path: "api/later")

    XCTAssertTrue(laterRead)
    XCTAssertEqual(refreshLoader.requests.count, 2)
  }

  func testInstallingNewCredentialsCancelsOldRefreshWithoutReplacingCredentials() async throws {
    let fixture = SessionFixture()
    let refreshLoader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let session = makeSession(fixture: fixture, refreshLoader: refreshLoader)
    try await session.install(fixture.credentials(expiresAt: fixture.past))
    let read = Task {
      try await session.authenticatedGET(path: "api/")
    }
    await fulfillment(of: [refreshLoader.started], timeout: 1)
    var replacement = fixture.credentials()
    replacement.accessToken = "replacement-access"
    replacement.refreshToken = "replacement-refresh"
    try await session.install(replacement)

    refreshLoader.succeed(with: refreshedTokenResponse, statusCode: 200)

    do {
      _ = try await read.value
      XCTFail("Expected the old refresh to be cancelled.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertEqual(currentCredentials, replacement)
    XCTAssertEqual(storedCredentials, replacement)
  }

  func testDisconnectCancelsAnActiveAPIRequest() async throws {
    let fixture = SessionFixture()
    let apiLoader = BlockingHomeAssistantLoader()
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: apiLoader,
      now: { [now = fixture.now] in now }
    )
    try await session.install(fixture.credentials())
    let read = Task {
      try await session.authenticatedGET(path: "api/")
    }
    await fulfillment(of: [apiLoader.started], timeout: 1)

    try await session.disconnect()

    do {
      _ = try await read.value
      XCTFail("Expected request cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(apiLoader.wasCancelled)
  }

  func testDisconnectRejectsLateSuccessFromLoaderThatIgnoresCancellation() async throws {
    let fixture = SessionFixture()
    let apiLoader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: apiLoader,
      now: { [now = fixture.now] in now }
    )
    try await session.install(fixture.credentials())
    let read = Task {
      try await session.authenticatedGET(path: "api/")
    }
    await fulfillment(of: [apiLoader.started], timeout: 1)

    try await session.disconnect()
    apiLoader.succeed(with: Data("late".utf8), statusCode: 200)

    do {
      _ = try await read.value
      XCTFail("Expected request cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(apiLoader.wasCancelled)
  }

  func testConnectionCheckRejectsSuccessAfterValidationCancelsCaller() async throws {
    let fixture = SessionFixture()
    let apiLoader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: apiLoader,
      now: { [now = fixture.now] in now }
    )
    try await session.install(fixture.credentials())
    let taskReference = ConnectionCheckTaskReference()
    let check = Task {
      try await session.checkConnection { _ in
        taskReference.cancel()
      }
    }
    taskReference.task = check
    await fulfillment(of: [apiLoader.started], timeout: 1)

    apiLoader.succeed(with: Data(#"{"message":"API running."}"#.utf8), statusCode: 200)

    do {
      _ = try await check.value
      XCTFail("Expected connection check cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testCredentialsRemainAvailableUntilDisconnectCommits() async throws {
    let fixture = SessionFixture()
    let store = BlockingDeleteCredentialStore()
    let session = HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now }
    )
    try await session.install(fixture.credentials())
    let disconnect = Task {
      try await session.disconnect()
    }
    await fulfillment(of: [store.deleteStarted], timeout: 1)

    let credentialsDuringDelete = await session.currentCredentials()
    XCTAssertEqual(credentialsDuringDelete, fixture.credentials())

    await store.completeDelete()
    try await disconnect.value
    let credentialsAfterDelete = await session.currentCredentials()
    XCTAssertNil(credentialsAfterDelete)
  }

  func testConcurrentFallbackReadsShareTheRecordedExternalRoute() async throws {
    let fixture = SessionFixture()
    let apiLoader = HostRoutingHomeAssistantLoader(
      internalHost: fixture.internalURL.host() ?? "",
      externalData: Data("external".utf8)
    )
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: apiLoader,
      now: { [now = fixture.now] in now }
    )
    try await session.install(fixture.credentials())

    async let first = session.authenticatedGET(path: "api/first")
    async let second = session.authenticatedGET(path: "api/second")
    let results = try await [first, second]

    XCTAssertEqual(results, [Data("external".utf8), Data("external".utf8)])
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertEqual(currentCredentials?.lastSuccessfulURL, fixture.externalURL)
    XCTAssertEqual(storedCredentials?.lastSuccessfulURL, fixture.externalURL)
  }

  private func makeSession(
    fixture: SessionFixture,
    refreshLoader: BlockingHomeAssistantLoader
  ) -> HomeAssistantSession {
    HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: refreshLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now }
    )
  }

  private var refreshedTokenResponse: Data {
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

  private static func reauthenticationResult(
    from session: HomeAssistantSession,
    path: String
  ) async -> Bool {
    do {
      _ = try await session.authenticatedGET(path: path)
      return false
    } catch HomeAssistantAPIError.reauthenticationRequired {
      return true
    } catch {
      return false
    }
  }

}

private final class ConnectionCheckTaskReference: @unchecked Sendable {
  private let lock = NSLock()
  private var storedTask: Task<Data, any Error>?

  var task: Task<Data, any Error>? {
    get { lock.withLock { storedTask } }
    set { lock.withLock { storedTask = newValue } }
  }

  func cancel() {
    task?.cancel()
  }
}

actor BlockingDeleteCredentialStore: HomeAssistantCredentialStoring {
  nonisolated let deleteStarted = XCTestExpectation(description: "Credential deletion started")
  private var value: HomeAssistantCredentials?
  private var deleteContinuation: CheckedContinuation<Void, Never>?

  func load() -> HomeAssistantCredentials? {
    value
  }

  func save(_ credentials: HomeAssistantCredentials) {
    value = credentials
  }

  func replace(
    _ credentials: HomeAssistantCredentials?,
    ifCurrentIs original: HomeAssistantCredentials?
  ) -> Bool {
    guard value == original else { return false }
    value = credentials
    return true
  }

  func delete() async {
    deleteStarted.fulfill()
    await withCheckedContinuation { continuation in
      deleteContinuation = continuation
    }
    value = nil
  }

  func completeDelete() {
    deleteContinuation?.resume()
    deleteContinuation = nil
  }
}

private final class HostRoutingHomeAssistantLoader:
  HomeAssistantHTTPDataLoading, @unchecked Sendable
{
  private let internalHost: String
  private let externalData: Data

  init(internalHost: String, externalData: Data) {
    self.internalHost = internalHost
    self.externalData = externalData
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    guard request.url?.host() != internalHost else {
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
    return (externalData, response)
  }
}

import XCTest

@testable import Bruce

final class HASessionRefreshConcurrencyTests: XCTestCase {
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
    let bothWaitersRegistered = expectation(description: "Both refresh waiters registered")
    let session = makeSession(
      fixture: fixture,
      refreshLoader: refreshLoader,
      refreshWaiterRegistered: { count in
        if count == 2 {
          bothWaitersRegistered.fulfill()
        }
      }
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))

    async let first = Self.reauthenticationResult(from: session, path: "api/first")
    async let second = Self.reauthenticationResult(from: session, path: "api/second")
    await fulfillment(of: [refreshLoader.started], timeout: 1)
    await fulfillment(of: [bothWaitersRegistered], timeout: 1)
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

  private func makeSession(
    fixture: SessionFixture,
    refreshLoader: BlockingHomeAssistantLoader,
    refreshWaiterRegistered: @escaping @Sendable (Int) -> Void = { _ in }
  ) -> HomeAssistantSession {
    HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: refreshLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now },
      refreshWaiterRegistered: refreshWaiterRegistered
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

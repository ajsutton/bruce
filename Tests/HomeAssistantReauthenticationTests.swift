import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantReauthenticationTests: XCTestCase {
  func testReauthenticationStartsImmediatelyWithoutAnotherConfirmation() async {
    let connection = ReauthenticationConnection()
    let store = HomeAssistantSetupStore(
      discovery: EmptyReauthenticationDiscovery(),
      connection: connection
    )
    await store.restoreSavedConnection()

    store.reauthenticate()
    await fulfillment(of: [connection.connectStarted], timeout: 1)

    guard case .readyForAuthentication(let candidate) = store.step else {
      return XCTFail("Expected authentication to start immediately.")
    }
    XCTAssertEqual(candidate.activeURL, connection.credentials.lastSuccessfulURL)
    XCTAssertEqual(connection.candidate, candidate)
    store.cancelAuthentication()
  }
}

@MainActor
private final class ReauthenticationConnection: HomeAssistantConnecting {
  let connectStarted = XCTestExpectation(description: "Reauthentication started")
  let credentials = HomeAssistantCredentials(
    instanceID: nil,
    instanceName: "Home",
    internalURL: URL(string: "https://home.example"),
    externalURL: nil,
    lastSuccessfulURL: URL(string: "https://home.example")
      ?? URL(fileURLWithPath: "/"),
    accessToken: "access",
    refreshToken: "refresh",
    tokenType: "Bearer",
    accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
    clientID: HomeAssistantOAuthConfiguration.release.clientID
  )
  private(set) var candidate: HomeAssistantConnectionCandidate?
  private var continuation: CheckedContinuation<HomeAssistantCredentials, any Error>?

  func authenticate(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    self.candidate = candidate
    connectStarted.fulfill()
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
    }
  }

  func restore() async throws -> HomeAssistantCredentials? {
    credentials
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    credentials
  }

  func disconnect() async throws {}

  func cancel() {
    continuation?.resume(throwing: CancellationError())
    continuation = nil
  }
}

private struct EmptyReauthenticationDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}

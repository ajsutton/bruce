import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantAccessStateTests: XCTestCase {
  func testTokenAndPreferredRouteChangesKeepTheSameAccessIdentity() throws {
    var refreshedCredentials = credentials
    refreshedCredentials.accessToken = "refreshed-access"
    refreshedCredentials.lastSuccessfulURL = try XCTUnwrap(credentials.externalURL)

    XCTAssertEqual(
      HomeAssistantAccessState.ready(credentials),
      .ready(refreshedCredentials)
    )
  }

  func testRestoringSavedAccessDoesNotWaitForAConnectionCheck() async {
    let connection = AccessStateConnection(credentials: credentials)
    let store = makeStore(connection: connection)

    await store.restoreSavedConnection()

    XCTAssertEqual(store.step, .connected(credentials))
    XCTAssertEqual(store.connectedCredentials, credentials)
    XCTAssertEqual(connection.connectionCheckCount, 0)
  }

  func testFailedManualCheckKeepsAccessReady() async {
    let connection = AccessStateConnection(credentials: credentials)
    let store = makeStore(connection: connection)
    await store.restoreSavedConnection()
    connection.connectionCheckError = URLError(.notConnectedToInternet)
    let checkFinished = expectation(description: "Connection check finished")
    checkFinished.assertForOverFulfill = false
    let subscription = store.objectWillChange.receive(on: RunLoop.main).sink {
      if store.connectionCheckState == .failed(.networkUnavailable) {
        checkFinished.fulfill()
      }
    }

    store.testConnection()
    await fulfillment(of: [checkFinished], timeout: 1)

    XCTAssertEqual(store.step, .connected(credentials))
    XCTAssertEqual(store.connectedCredentials, credentials)
    let presentation = HomeAssistantPresentation(
      step: store.step,
      connectionCheckState: store.connectionCheckState
    )
    XCTAssertEqual(presentation.access, .ready(credentials))
    XCTAssertEqual(presentation.connectionProblem, .unavailable)
    withExtendedLifetime(subscription) {}
  }

  func testReleasingStoreCancelsBlockedManualCheck() async {
    let connection = AccessStateConnection(credentials: credentials)
    connection.blocksConnectionCheck = true
    var store: HomeAssistantSetupStore? = makeStore(connection: connection)
    await store?.restoreSavedConnection()
    weak var releasedStore: HomeAssistantSetupStore?
    releasedStore = store

    store?.testConnection()
    await fulfillment(of: [connection.connectionCheckStarted], timeout: 1)
    store = nil
    await fulfillment(of: [connection.connectionCheckCancelled], timeout: 1)

    XCTAssertNil(releasedStore)
  }

  private func makeStore(
    connection: AccessStateConnection
  ) -> HomeAssistantSetupStore {
    HomeAssistantSetupStore(
      discovery: EmptyAccessStateDiscovery(),
      connection: connection
    )
  }

  private var credentials: HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: nil,
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(string: "http://home.local:8123")
        ?? URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

@MainActor
private final class AccessStateConnection: HomeAssistantConnecting {
  let credentials: HomeAssistantCredentials
  var connectionCheckError: (any Error)?
  var blocksConnectionCheck = false
  private(set) var connectionCheckCount = 0
  private let connectionCheckGate = AccessStateConnectionCheckGate()

  var connectionCheckStarted: XCTestExpectation { connectionCheckGate.started }
  var connectionCheckCancelled: XCTestExpectation { connectionCheckGate.cancelled }

  init(credentials: HomeAssistantCredentials) {
    self.credentials = credentials
  }

  func connect(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    credentials
  }

  func restore() async throws -> HomeAssistantCredentials? { credentials }

  func testConnection() async throws -> HomeAssistantCredentials {
    connectionCheckCount += 1
    if let connectionCheckError {
      throw connectionCheckError
    }
    if blocksConnectionCheck {
      try await connectionCheckGate.wait()
    }
    return credentials
  }

  func disconnect() async throws {}
  func cancel() {}
}

private final class AccessStateConnectionCheckGate: @unchecked Sendable {
  let started = XCTestExpectation(description: "Connection check started")
  let cancelled = XCTestExpectation(description: "Connection check cancelled")
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, any Error>?

  func wait() async throws {
    started.fulfill()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        lock.withLock {
          self.continuation = continuation
        }
      }
    } onCancel: {
      let continuation = lock.withLock {
        let continuation = self.continuation
        self.continuation = nil
        return continuation
      }
      cancelled.fulfill()
      continuation?.resume(throwing: CancellationError())
    }
  }
}

private struct EmptyAccessStateDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { $0.finish() }
  }
}

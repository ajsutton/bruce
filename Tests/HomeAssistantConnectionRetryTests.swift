import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantConnectionRetryTests: XCTestCase {
  func testNetworkFailurePeriodicallyRetriesUntilConnectionSucceeds() async {
    let connection = RetryTestConnection(credentials: credentials)
    let delay = ControlledHomeEnergyDelay(delayCount: 2)
    let store = makeStore(connection: connection, sleep: delay.sleep)
    let connected = expectation(description: "Automatic connection retry succeeded")
    let subscription = store.$step.sink { step in
      if case .connected = step {
        connected.fulfill()
      }
    }

    await store.restoreSavedConnection()
    await fulfillment(of: [delay.started(at: 0)], timeout: 1)
    delay.finish(0)
    await fulfillment(of: [delay.completed(at: 0), delay.started(at: 1)], timeout: 1)
    connection.connectionCheckError = nil
    delay.finish(1)
    await fulfillment(of: [connected], timeout: 1)

    XCTAssertEqual(connection.connectionCheckCount, 3)
    XCTAssertEqual(store.step, .connected(credentials))
    XCTAssertEqual(store.connectionCheckState, .succeeded)
    withExtendedLifetime(subscription) {}
  }

  func testChangingServerCancelsScheduledConnectionRetry() async {
    let connection = RetryTestConnection(credentials: credentials)
    let delay = NonCooperativeRetryDelay()
    let store = makeStore(connection: connection, sleep: delay.sleep)

    await store.restoreSavedConnection()
    await fulfillment(of: [delay.started], timeout: 1)
    store.changeServer()
    delay.finish()
    await fulfillment(of: [delay.completed], timeout: 1)

    XCTAssertEqual(connection.connectionCheckCount, 1)
    XCTAssertEqual(store.step, .introduction)
  }

  func testReleasingStoreCancelsBlockedConnectionCheck() async {
    let connection = RetryTestConnection(credentials: credentials)
    connection.connectionCheckError = nil
    var store: HomeAssistantSetupStore? = makeStore(connection: connection) { _ in }
    defer { connection.finishBlockedConnectionCheck() }
    await store?.restoreSavedConnection()
    connection.blocksConnectionCheck = true
    weak var releasedStore: HomeAssistantSetupStore?
    releasedStore = store
    store?.testConnection()
    await fulfillment(of: [connection.connectionCheckStarted], timeout: 1)

    store = nil
    await fulfillment(of: [connection.connectionCheckCancelled], timeout: 1)

    XCTAssertNil(releasedStore)
  }

  private func makeStore(
    connection: RetryTestConnection,
    sleep: @escaping @Sendable (Duration) async throws -> Void
  ) -> HomeAssistantSetupStore {
    HomeAssistantSetupStore(
      discovery: EmptyConnectionRetryDiscovery(),
      connection: connection,
      connectionRetryDelay: .seconds(60),
      sleep: sleep
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
private final class RetryTestConnection: HomeAssistantConnecting {
  let credentials: HomeAssistantCredentials
  var connectionCheckError: (any Error)? = URLError(.notConnectedToInternet)
  private(set) var connectionCheckCount = 0
  var blocksConnectionCheck = false
  private let connectionCheckGate = RetryConnectionCheckGate()

  var connectionCheckStarted: XCTestExpectation {
    connectionCheckGate.started
  }

  var connectionCheckCancelled: XCTestExpectation {
    connectionCheckGate.cancelled
  }

  init(credentials: HomeAssistantCredentials) {
    self.credentials = credentials
  }

  func connect(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    credentials
  }

  func restore() async throws -> HomeAssistantCredentials? {
    credentials
  }

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

  func finishBlockedConnectionCheck() {
    connectionCheckGate.finish()
  }

  func disconnect() async throws {}

  func cancel() {}
}

private final class RetryConnectionCheckGate: @unchecked Sendable {
  let started = XCTestExpectation(description: "Connection check started")
  let cancelled = XCTestExpectation(description: "Connection check cancelled")

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, any Error>?
  private var isCancelled = false
  private var shouldFinish = false

  func wait() async throws {
    started.fulfill()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let result = lock.withLock {
          if isCancelled {
            return RetryConnectionCheckGateResult.cancelled
          }
          if shouldFinish {
            return .finished
          }
          self.continuation = continuation
          return .waiting
        }
        switch result {
        case .cancelled:
          continuation.resume(throwing: CancellationError())
        case .finished:
          continuation.resume()
        case .waiting:
          break
        }
      }
    } onCancel: {
      cancel()
    }
  }

  func finish() {
    let continuation = lock.withLock {
      shouldFinish = true
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume()
  }

  private func cancel() {
    let continuation = lock.withLock {
      isCancelled = true
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    cancelled.fulfill()
    continuation?.resume(throwing: CancellationError())
  }
}

private enum RetryConnectionCheckGateResult {
  case cancelled
  case finished
  case waiting
}

private final class NonCooperativeRetryDelay: @unchecked Sendable {
  let started = XCTestExpectation(description: "Retry delay started")
  let completed = XCTestExpectation(description: "Retry delay completed")

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  func sleep(_: Duration) async throws {
    await withCheckedContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
    completed.fulfill()
  }

  func finish() {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume()
  }
}

private struct EmptyConnectionRetryDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}

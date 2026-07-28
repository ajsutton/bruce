import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantRestoreRemovalTests: XCTestCase {
  func testSavedConnectionDetailsAreAvailableWhileConnectionCheckIsRunning() async {
    let connection = RestoreCancellationConnection()
    connection.blocksRestore = false
    connection.restoredCredentials = credentials
    connection.blocksConnectionCheck = true
    let store = makeStore(connection: connection)
    let restore = Task {
      await store.restoreSavedConnection()
    }
    await fulfillment(of: [connection.connectionCheckStarted], timeout: 1)

    XCTAssertEqual(store.step, .configured(credentials))
    XCTAssertEqual(store.connectedCredentials, credentials)
    XCTAssertEqual(store.connectionCheckState, .checking)

    connection.completeConnectionCheck(with: credentials)
    _ = await restore.value
  }

  func testRemovingConnectionDuringRestoreCancelsRestore() async {
    let connection = RestoreCancellationConnection()
    let store = makeStore(connection: connection)
    let restoreFinished = expectation(description: "Restore finished")
    let restore = Task {
      await store.restoreSavedConnection()
      restoreFinished.fulfill()
    }
    await fulfillment(of: [connection.restoreStarted], timeout: 1)
    let connectionRemoved = expectation(description: "Saved connection removed")
    connectionRemoved.assertForOverFulfill = false
    let subscription = store.$step.sink { step in
      if step == .introduction {
        connectionRemoved.fulfill()
      }
    }

    store.disconnect()
    await fulfillment(of: [connectionRemoved, restoreFinished], timeout: 1)
    _ = await restore.value

    XCTAssertTrue(connection.wasCancelled)
    XCTAssertFalse(store.isDisconnecting)
    XCTAssertEqual(store.step, .introduction)
    XCTAssertNil(store.connectedCredentials)
    withExtendedLifetime(subscription) {}
  }

  func testFailedRemovalDuringRestoreShowsRecoveryInsteadOfProgress() async {
    let connection = RestoreCancellationConnection()
    connection.disconnectError = HomeAssistantCredentialStoreError.keychainFailure(-1)
    let store = makeStore(connection: connection)
    let restoreFinished = expectation(description: "Restore finished")
    let restore = Task {
      await store.restoreSavedConnection()
      restoreFinished.fulfill()
    }
    await fulfillment(of: [connection.restoreStarted], timeout: 1)
    let failureShown = expectation(description: "Removal failure shown")
    failureShown.assertForOverFulfill = false
    let subscription = store.objectWillChange.receive(on: RunLoop.main).sink {
      if store.connectionCheckState == .disconnectFailed {
        failureShown.fulfill()
      }
    }

    store.disconnect()
    await fulfillment(of: [failureShown, restoreFinished], timeout: 1)
    _ = await restore.value
    let presentation = HomeAssistantPresentation(
      step: store.step,
      connectionCheckState: store.connectionCheckState
    )

    XCTAssertTrue(connection.wasCancelled)
    XCTAssertFalse(store.isDisconnecting)
    XCTAssertEqual(store.step, .restoring)
    XCTAssertEqual(store.connectionCheckState, .disconnectFailed)
    XCTAssertFalse(presentation.isConnecting)
    XCTAssertEqual(
      presentation.connectionProblem,
      .removalFailed
    )
    withExtendedLifetime(subscription) {}
  }

  func testRetryingFailedRemovalClearsFailureWhileDisconnecting() async {
    let connection = RestoreCancellationConnection()
    connection.disconnectError = HomeAssistantCredentialStoreError.keychainFailure(-1)
    let store = makeStore(connection: connection)
    let restoreFinished = expectation(description: "Restore finished")
    let restore = Task {
      await store.restoreSavedConnection()
      restoreFinished.fulfill()
    }
    await fulfillment(of: [connection.restoreStarted], timeout: 1)
    let failureShown = expectation(description: "Removal failure shown")
    failureShown.assertForOverFulfill = false
    let subscription = store.objectWillChange.receive(on: RunLoop.main).sink {
      if store.connectionCheckState == .disconnectFailed {
        failureShown.fulfill()
      }
    }
    store.disconnect()
    await fulfillment(of: [failureShown, restoreFinished], timeout: 1)
    connection.disconnectError = nil
    connection.blocksDisconnect = true

    store.disconnect()
    await fulfillment(of: [connection.disconnectStarted], timeout: 1)

    XCTAssertTrue(store.isDisconnecting)
    XCTAssertEqual(store.connectionCheckState, .idle)

    let connectionRemoved = expectation(description: "Saved connection removed")
    let removalSubscription = store.$step.sink { step in
      if step == .introduction {
        connectionRemoved.fulfill()
      }
    }
    connection.completeDisconnect()
    await fulfillment(of: [connectionRemoved], timeout: 1)
    _ = await restore.value
    withExtendedLifetime((subscription, removalSubscription)) {}
  }

  private func makeStore(
    connection: RestoreCancellationConnection
  ) -> HomeAssistantSetupStore {
    HomeAssistantSetupStore(
      discovery: EmptyRestoreRemovalDiscovery(),
      connection: connection
    )
  }

  private var credentials: HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(string: "https://home.example")
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
private final class RestoreCancellationConnection: HomeAssistantConnecting {
  let restoreStarted = XCTestExpectation(description: "Restore started")
  let connectionCheckStarted = XCTestExpectation(description: "Connection check started")
  let disconnectStarted = XCTestExpectation(description: "Disconnect started")
  var disconnectError: (any Error)?
  var restoredCredentials: HomeAssistantCredentials?
  var blocksRestore = true
  var blocksConnectionCheck = false
  var blocksDisconnect = false
  private(set) var wasCancelled = false
  private var disconnectContinuation: CheckedContinuation<Void, Never>?
  private var restoreContinuation: CheckedContinuation<HomeAssistantCredentials?, any Error>?
  private var connectionCheckContinuation: CheckedContinuation<HomeAssistantCredentials, any Error>?

  func connect(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    throw HomeAssistantAPIError.noCredentials
  }

  func restore() async throws -> HomeAssistantCredentials? {
    guard blocksRestore else {
      return restoredCredentials
    }
    restoreStarted.fulfill()
    return try await withCheckedThrowingContinuation { continuation in
      restoreContinuation = continuation
    }
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    guard blocksConnectionCheck else {
      throw HomeAssistantAPIError.noCredentials
    }
    connectionCheckStarted.fulfill()
    return try await withCheckedThrowingContinuation { continuation in
      connectionCheckContinuation = continuation
    }
  }

  func disconnect() async throws {
    if let disconnectError {
      throw disconnectError
    }
    guard blocksDisconnect else {
      return
    }
    disconnectStarted.fulfill()
    await withCheckedContinuation { continuation in
      disconnectContinuation = continuation
    }
  }

  func cancel() {
    wasCancelled = true
    disconnectContinuation?.resume()
    disconnectContinuation = nil
    restoreContinuation?.resume(throwing: CancellationError())
    restoreContinuation = nil
    connectionCheckContinuation?.resume(throwing: CancellationError())
    connectionCheckContinuation = nil
  }

  func completeDisconnect() {
    disconnectContinuation?.resume()
    disconnectContinuation = nil
  }

  func completeConnectionCheck(with credentials: HomeAssistantCredentials) {
    connectionCheckContinuation?.resume(returning: credentials)
    connectionCheckContinuation = nil
  }
}

private struct EmptyRestoreRemovalDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}

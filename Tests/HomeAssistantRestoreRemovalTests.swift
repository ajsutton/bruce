import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantRestoreRemovalTests: XCTestCase {
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
}

@MainActor
private final class RestoreCancellationConnection: HomeAssistantConnecting {
  let restoreStarted = XCTestExpectation(description: "Restore started")
  let disconnectStarted = XCTestExpectation(description: "Disconnect started")
  var disconnectError: (any Error)?
  var blocksDisconnect = false
  private(set) var wasCancelled = false
  private var disconnectContinuation: CheckedContinuation<Void, Never>?
  private var restoreContinuation: CheckedContinuation<HomeAssistantCredentials?, any Error>?

  func connect(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    throw HomeAssistantAPIError.noCredentials
  }

  func restore() async throws -> HomeAssistantCredentials? {
    restoreStarted.fulfill()
    return try await withCheckedThrowingContinuation { continuation in
      restoreContinuation = continuation
    }
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    throw HomeAssistantAPIError.noCredentials
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
  }

  func completeDisconnect() {
    disconnectContinuation?.resume()
    disconnectContinuation = nil
  }
}

private struct EmptyRestoreRemovalDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}

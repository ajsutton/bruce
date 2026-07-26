import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantSetupAuthenticationTests: XCTestCase {
  func testSuccessfulAuthenticationCompletesSetup() async {
    let connection = ControlledHomeAssistantConnection()
    let store = makeStore(connection: connection)
    let stepChanged = expectation(description: "Setup connected")
    let subscription = store.$step.sink { step in
      if case .connected = step {
        stepChanged.fulfill()
      }
    }
    prepareManualCandidate(in: store)

    store.requestAuthentication()
    await fulfillment(of: [connection.connectStarted], timeout: 1)
    connection.succeed(with: credentials())
    await fulfillment(of: [stepChanged], timeout: 1)

    XCTAssertEqual(store.connectedCredentials, credentials())
    XCTAssertEqual(store.connectionCheckState, .succeeded)
    withExtendedLifetime(subscription) {}
  }

  func testAuthenticationCancellationReturnsToConfirmedServer() async {
    let connection = ControlledHomeAssistantConnection()
    let store = makeStore(connection: connection)
    prepareManualCandidate(in: store)
    guard case .confirmation(let candidate) = store.step else {
      return XCTFail("Expected a confirmed server.")
    }

    store.requestAuthentication()
    await fulfillment(of: [connection.connectStarted], timeout: 1)
    store.cancelAuthentication()

    XCTAssertEqual(store.step, .confirmation(candidate))
    XCTAssertTrue(connection.wasCancelled)
    XCTAssertNil(store.connectedCredentials)
  }

  func testSetupCancellationIgnoresLateAuthenticationCompletion() async {
    let connection = ControlledHomeAssistantConnection()
    connection.ignoresCancellation = true
    let completionObserved = expectation(description: "Late connection completed")
    connection.connectCompletionObserved = completionObserved
    let store = makeStore(connection: connection)
    prepareManualCandidate(in: store)

    store.requestAuthentication()
    await fulfillment(of: [connection.connectStarted], timeout: 1)
    store.cancel()
    connection.succeed(with: credentials())
    await fulfillment(of: [completionObserved], timeout: 1)

    XCTAssertEqual(store.step, .cancelled)
    XCTAssertNil(store.connectedCredentials)
  }

  func testRejectedAuthenticationUsesDirectRecoveryState() async {
    let connection = ControlledHomeAssistantConnection()
    let store = makeStore(connection: connection)
    let stepChanged = expectation(description: "Authentication failure shown")
    let subscription = store.$step.sink { step in
      if case .authenticationFailed = step {
        stepChanged.fulfill()
      }
    }
    prepareManualCandidate(in: store)

    store.requestAuthentication()
    await fulfillment(of: [connection.connectStarted], timeout: 1)
    connection.fail(with: HomeAssistantAuthenticationError.authorizationRejected(nil))
    await fulfillment(of: [stepChanged], timeout: 1)

    guard case .authenticationFailed(_, let failure) = store.step else {
      return XCTFail("Expected an authentication failure.")
    }
    XCTAssertEqual(failure.problem, .rejected)
    withExtendedLifetime(subscription) {}
  }

  func testAuthenticationFailureIncludesTheUnderlyingDiagnostic() async {
    let connection = ControlledHomeAssistantConnection()
    let store = makeStore(connection: connection)
    let stepChanged = expectation(description: "Authentication failure shown")
    let subscription = store.$step.sink { step in
      if case .authenticationFailed = step {
        stepChanged.fulfill()
      }
    }
    prepareManualCandidate(in: store)

    store.requestAuthentication()
    await fulfillment(of: [connection.connectStarted], timeout: 1)
    connection.fail(
      with: NSError(
        domain: "AuthenticationServices.WebAuthenticationSession",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "The test authentication failed."]
      ))
    await fulfillment(of: [stepChanged], timeout: 1)

    guard case .authenticationFailed(_, let failure) = store.step else {
      return XCTFail("Expected an authentication failure.")
    }
    XCTAssertEqual(
      failure.diagnostic,
      "The test authentication failed. "
        + "(AuthenticationServices.WebAuthenticationSession, code 1)"
    )
    withExtendedLifetime(subscription) {}
  }

  func testAuthenticationFailureDoesNotRepeatADomainAlreadyInTheDescription() {
    let failure = HomeAssistantAuthenticationFailure(
      error: NSError(
        domain: "AuthenticationServices.WebAuthenticationSession",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "The operation failed. (AuthenticationServices.WebAuthenticationSession error 1.)"
        ]
      )
    )

    XCTAssertEqual(
      failure.diagnostic,
      "The operation failed. (AuthenticationServices.WebAuthenticationSession error 1.)"
    )
  }

  func testSavedConnectionIsRestoredOnLaunch() async {
    let connection = ControlledHomeAssistantConnection()
    connection.restoredCredentials = credentials()
    let store = makeStore(connection: connection)

    await store.restoreSavedConnection()

    XCTAssertEqual(store.step, .connected(credentials()))
    XCTAssertEqual(store.connectedCredentials, credentials())
  }

  func testRestoreFailureShowsRecoveryState() async {
    let connection = ControlledHomeAssistantConnection()
    connection.restoreError = HomeAssistantCredentialStoreError.keychainFailure(-1)
    let store = makeStore(connection: connection)

    await store.restoreSavedConnection()

    XCTAssertEqual(store.step, .restoreFailed)
    XCTAssertNil(store.connectedCredentials)
  }

  func testChangingServerIgnoresLateRestoreCompletion() async {
    let connection = ControlledHomeAssistantConnection()
    connection.blocksRestore = true
    connection.ignoresCancellation = true
    let store = makeStore(connection: connection)
    let restore = Task {
      await store.restoreSavedConnection()
    }
    await fulfillment(of: [connection.restoreStarted], timeout: 1)

    store.changeServer()
    connection.completeRestore(with: credentials())
    await restore.value

    XCTAssertEqual(store.step, .introduction)
    XCTAssertNil(store.connectedCredentials)
  }

  func testChangingServerIgnoresLateConnectionCheck() async {
    let connection = ControlledHomeAssistantConnection()
    connection.restoredCredentials = credentials()
    let store = makeStore(connection: connection)
    await store.restoreSavedConnection()
    connection.blocksConnectionCheck = true
    connection.ignoresCancellation = true
    let completionObserved = expectation(description: "Late connection check completed")
    connection.connectionCheckCompletionObserved = completionObserved

    store.testConnection()
    await fulfillment(of: [connection.connectionCheckStarted], timeout: 1)
    store.changeServer()
    connection.completeConnectionCheck(with: credentials(instanceName: "Late Home"))
    await fulfillment(of: [completionObserved], timeout: 1)

    XCTAssertEqual(store.step, .introduction)
    XCTAssertEqual(store.connectedCredentials, credentials())
  }

  func testDisconnectFailureKeepsTheActiveConnectionAndShowsFailure() async {
    let connection = ControlledHomeAssistantConnection()
    connection.restoredCredentials = credentials()
    connection.disconnectError = HomeAssistantCredentialStoreError.keychainFailure(-1)
    let store = makeStore(connection: connection)
    await store.restoreSavedConnection()
    let failureShown = expectation(description: "Disconnect failure shown")
    failureShown.assertForOverFulfill = false
    let subscription = store.objectWillChange.receive(on: RunLoop.main).sink {
      if store.connectionCheckState == .disconnectFailed {
        failureShown.fulfill()
      }
    }

    store.disconnect()
    await fulfillment(of: [failureShown], timeout: 1)

    XCTAssertEqual(store.step, .connected(credentials()))
    XCTAssertEqual(store.connectedCredentials, credentials())
    XCTAssertEqual(store.connectionCheckState, .disconnectFailed)
    withExtendedLifetime(subscription) {}
  }

  func testServerFailureMapsToUnavailableRecovery() {
    let problem = HomeAssistantAuthenticationProblemMapper.problem(
      for: HomeAssistantAuthenticationError.serverRejectedRequest(
        statusCode: 503,
        description: nil
      )
    )

    XCTAssertEqual(problem, .unavailable)
  }

  private func makeStore(
    connection: ControlledHomeAssistantConnection
  ) -> HomeAssistantSetupStore {
    HomeAssistantSetupStore(
      discovery: EmptySetupAuthenticationDiscovery(),
      connection: connection
    )
  }

  private func prepareManualCandidate(in store: HomeAssistantSetupStore) {
    store.showManualEntry()
    store.updateManualAddress("https://home.example")
    store.validateManualAddress()
  }

  private func credentials(instanceName: String = "home.example") -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: nil,
      instanceName: instanceName,
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
  }
}

@MainActor
private final class ControlledHomeAssistantConnection: HomeAssistantConnecting {
  let connectStarted = XCTestExpectation(description: "Connection started")
  let restoreStarted = XCTestExpectation(description: "Restore started")
  let connectionCheckStarted = XCTestExpectation(description: "Connection check started")
  var restoredCredentials: HomeAssistantCredentials?
  var restoreError: (any Error)?
  var disconnectError: (any Error)?
  var blocksRestore = false
  var blocksConnectionCheck = false
  var ignoresCancellation = false
  var connectCompletionObserved: XCTestExpectation?
  var connectionCheckCompletionObserved: XCTestExpectation?
  private(set) var wasCancelled = false
  private var continuation: CheckedContinuation<HomeAssistantCredentials, any Error>?
  private var restoreContinuation: CheckedContinuation<HomeAssistantCredentials?, any Error>?
  private var connectionCheckContinuation: CheckedContinuation<HomeAssistantCredentials, any Error>?

  func connect(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    connectStarted.fulfill()
    let credentials = try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
    }
    connectCompletionObserved?.fulfill()
    return credentials
  }

  func restore() async throws -> HomeAssistantCredentials? {
    if let restoreError {
      throw restoreError
    }
    guard blocksRestore else {
      return restoredCredentials
    }
    restoreStarted.fulfill()
    return try await withCheckedThrowingContinuation { continuation in
      restoreContinuation = continuation
    }
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    if blocksConnectionCheck {
      connectionCheckStarted.fulfill()
      let credentials = try await withCheckedThrowingContinuation { continuation in
        connectionCheckContinuation = continuation
      }
      connectionCheckCompletionObserved?.fulfill()
      return credentials
    }
    guard let restoredCredentials else {
      throw HomeAssistantAPIError.noCredentials
    }
    return restoredCredentials
  }

  func disconnect() async throws {
    if let disconnectError {
      throw disconnectError
    }
  }

  func cancel() {
    wasCancelled = true
    guard !ignoresCancellation else {
      return
    }
    continuation?.resume(throwing: CancellationError())
    continuation = nil
    restoreContinuation?.resume(throwing: CancellationError())
    restoreContinuation = nil
    connectionCheckContinuation?.resume(throwing: CancellationError())
    connectionCheckContinuation = nil
  }

  func succeed(with credentials: HomeAssistantCredentials) {
    continuation?.resume(returning: credentials)
    continuation = nil
  }

  func fail(with error: any Error) {
    continuation?.resume(throwing: error)
    continuation = nil
  }

  func completeRestore(with credentials: HomeAssistantCredentials?) {
    restoreContinuation?.resume(returning: credentials)
    restoreContinuation = nil
  }

  func completeConnectionCheck(with credentials: HomeAssistantCredentials) {
    connectionCheckContinuation?.resume(returning: credentials)
    connectionCheckContinuation = nil
  }
}

private struct EmptySetupAuthenticationDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}

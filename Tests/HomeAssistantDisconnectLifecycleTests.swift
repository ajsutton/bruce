import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantDisconnectLifecycleTests: XCTestCase {
  func testFailureDoesNotRestoreAccessWhenSignInIsRequired() async {
    let connection = DisconnectLifecycleConnection()
    connection.disconnectError = HomeAssistantCredentialStoreError.keychainFailure(-1)
    let store = makeStore(connection: connection)
    await store.restoreSavedConnection()
    store.requireReauthentication()

    store.disconnect()
    await fulfillment(of: [connection.disconnectStarted], timeout: 1)
    await Task.yield()

    XCTAssertEqual(store.step, .configured(credentials()))
    let presentation = HomeAssistantPresentation(
      step: store.step,
      connectionCheckState: store.connectionCheckState
    )
    XCTAssertEqual(presentation.access, .requiresUserAction)
    XCTAssertEqual(presentation.connectionProblem, .disconnectFailed)
  }

  func testDuplicateDisconnectDoesNotReplaceActiveOperation() async {
    let connection = DisconnectLifecycleConnection(blocksDisconnect: true)
    let store = makeStore(connection: connection)
    await store.restoreSavedConnection()

    store.disconnect()
    await fulfillment(of: [connection.disconnectStarted], timeout: 1)
    store.disconnect()
    connection.resumeDisconnect()
    await Task.yield()
    await Task.yield()

    XCTAssertEqual(connection.disconnectCount, 1)
    XCTAssertFalse(store.isDisconnecting)
  }

  private func makeStore(
    connection: DisconnectLifecycleConnection
  ) -> HomeAssistantSetupStore {
    HomeAssistantSetupStore(
      discovery: EmptyDisconnectLifecycleDiscovery(),
      connection: connection
    )
  }

  private func credentials() -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "instance",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(string: "https://home.example")!,
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: .distantFuture,
      clientID: URL(string: "https://client.example")!
    )
  }
}

private final class DisconnectLifecycleConnection: HomeAssistantConnecting, @unchecked Sendable {
  let disconnectStarted = XCTestExpectation(description: "Disconnect started")
  var disconnectError: (any Error)?
  private(set) var disconnectCount = 0
  private let blocksDisconnect: Bool
  private var disconnectContinuation: CheckedContinuation<Void, Never>?

  init(blocksDisconnect: Bool = false) {
    self.blocksDisconnect = blocksDisconnect
  }

  func restore() async throws -> HomeAssistantCredentials? {
    HomeAssistantCredentials(
      instanceID: "instance",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(string: "https://home.example")!,
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: .distantFuture,
      clientID: URL(string: "https://client.example")!
    )
  }

  func connect(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    guard let credentials = try await restore() else {
      throw HomeAssistantAPIError.noCredentials
    }
    return credentials
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    guard let credentials = try await restore() else {
      throw HomeAssistantAPIError.noCredentials
    }
    return credentials
  }

  func disconnect() async throws {
    disconnectCount += 1
    disconnectStarted.fulfill()
    if blocksDisconnect {
      await withCheckedContinuation { disconnectContinuation = $0 }
    }
    if let disconnectError { throw disconnectError }
  }

  func resumeDisconnect() {
    disconnectContinuation?.resume()
    disconnectContinuation = nil
  }

  func cancel() {}
}

private struct EmptyDisconnectLifecycleDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { $0.finish() }
  }
}

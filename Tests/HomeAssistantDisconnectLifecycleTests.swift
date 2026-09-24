import Combine
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

    let finished = expectation(description: "Failed disconnect restored configured step")
    let observation = store.$step.dropFirst().filter {
      if case .configured = $0 { return true }
      return false
    }.prefix(1).sink { _ in finished.fulfill() }
    store.disconnect()
    await fulfillment(of: [finished], timeout: 1)
    withExtendedLifetime(observation) {}

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

    let finished = expectation(description: "Disconnect completed")
    let observation = store.$step.dropFirst().filter {
      if case .introduction = $0 { return true }
      return false
    }.prefix(1).sink { _ in finished.fulfill() }
    store.disconnect()
    await fulfillment(of: [connection.disconnectStarted], timeout: 1)
    store.disconnect()
    connection.resumeDisconnect()
    await fulfillment(of: [finished], timeout: 1)
    withExtendedLifetime(observation) {}

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
  private let lock = NSLock()
  var disconnectError: (any Error)?
  private var storedDisconnectCount = 0
  var disconnectCount: Int { lock.withLock { storedDisconnectCount } }
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

  func authenticate(
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
    lock.withLock { storedDisconnectCount += 1 }
    if blocksDisconnect {
      await withCheckedContinuation { continuation in
        lock.withLock { disconnectContinuation = continuation }
        disconnectStarted.fulfill()
      }
    } else {
      disconnectStarted.fulfill()
    }
    if let disconnectError { throw disconnectError }
  }

  func resumeDisconnect() {
    let continuation = lock.withLock {
      defer { disconnectContinuation = nil }
      return disconnectContinuation
    }
    continuation?.resume()
  }

  func cancel() {}
}

private struct EmptyDisconnectLifecycleDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { $0.finish() }
  }
}

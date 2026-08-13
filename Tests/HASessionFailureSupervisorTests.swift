import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HASessionFailureSupervisorTests: XCTestCase {
  func testFailedInstallDoesNotInvalidateActiveSupervisorSession() async throws {
    let harness = try await makeHarness()
    await harness.store.failNext(.save)
    var replacement = harness.credentials
    replacement.accessToken = "replacement"

    await assertFailureKeepsSupervisorLive(harness) {
      try await harness.session.install(replacement)
    }
  }

  func testFailedRestoreDoesNotInvalidateActiveSupervisorSession() async throws {
    let harness = try await makeHarness()
    await harness.store.failNext(.load)

    await assertFailureKeepsSupervisorLive(harness) {
      _ = try await harness.session.restore()
    }
  }

  func testFailedDisconnectDoesNotInvalidateActiveSupervisorSession() async throws {
    let harness = try await makeHarness()
    await harness.store.blockNextDelete()
    let disconnect = Task { try await makeCoordinator(harness).disconnect() }
    await fulfillment(of: [harness.store.deleteStarted], timeout: 5)
    let arrivingProbe = AsyncThrowingStreamTestProbe(await harness.supervisor.stateUpdates())
    await harness.store.finishBlockedDelete(throwing: true)
    await assertCredentialFailure(disconnect)

    await fulfillment(of: [harness.probe.received(at: 2)], timeout: 5)
    harness.replacementConnection.yield(
      stateChangedEvent(entityID: "climate.bedroom", value: 22)
    )
    await fulfillment(of: [harness.probe.received(at: 3)], timeout: 5)
    let recovered = try harness.probe.value(at: 3)
    await arrivingProbe.cancel()
    await harness.probe.cancel()
    await harness.supervisor.stop()

    XCTAssertEqual(recovered.phase, .live)
    XCTAssertEqual(harness.connector.connectionCount, 2)
  }

  func testExplicitStopSupersedesFailedDisconnectRecovery() async throws {
    let harness = try await makeHarness()
    await harness.store.blockNextDelete()
    let disconnect = Task { try await makeCoordinator(harness).disconnect() }
    await fulfillment(of: [harness.store.deleteStarted], timeout: 5)

    await harness.supervisor.stop()
    await harness.store.finishBlockedDelete(throwing: true)
    await assertCredentialFailure(disconnect)

    XCTAssertEqual(harness.connector.connectionCount, 1)
  }

  private func makeHarness() async throws -> FailureHarness {
    let store = ControllablyFailingCredentialStore()
    let events = HomeAssistantCredentialEvents()
    let authenticationLoader = QueueHomeAssistantLoader()
    let apiLoader = QueueHomeAssistantLoader()
    apiLoader.results = [21, 21].map {
      .success(temperatureStates(value: $0), statusCode: 200)
    }
    let session = HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: authenticationLoader,
        now: { Date(timeIntervalSince1970: 20_000) }
      ),
      loader: apiLoader,
      now: { Date(timeIntervalSince1970: 20_000) },
      credentialEvents: events
    )
    let credentials = SupervisorFixture(snapshotValues: []).credentials
    try await session.install(credentials)
    let connection = ScriptedHomeAssistantConnection()
    let replacementConnection = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(
      connections: [connection, replacementConnection]
    )
    let supervisor = HomeAssistantConnectionSupervisor(
      session: session,
      connector: connector,
      credentialEvents: events,
      retryPolicy: HomeAssistantConnectionRetryPolicy(
        initialWindow: 0,
        maximumWindow: 0,
        randomUnit: { 0 }
      )
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)
    return FailureHarness(
      store: store,
      session: session,
      credentials: credentials,
      connection: connection,
      replacementConnection: replacementConnection,
      connector: connector,
      supervisor: supervisor,
      probe: probe
    )
  }

  private func assertFailureKeepsSupervisorLive(
    _ harness: FailureHarness,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected credential persistence to fail.")
    } catch HomeAssistantCredentialStoreError.keychainFailure {
    } catch {
      XCTFail("Unexpected failure: \(error)")
    }

    harness.connection.yield(
      stateChangedEvent(entityID: "climate.bedroom", value: 22)
    )
    await fulfillment(of: [harness.probe.received(at: 1)], timeout: 5)
    let update = try? harness.probe.value(at: 1)
    let connectionWasCancelled = harness.connection.isCancelled
    await harness.probe.cancel()
    await harness.supervisor.stop()

    XCTAssertEqual(update?.phase, .live)
    XCTAssertEqual(harness.connector.connectionCount, 1)
    XCTAssertFalse(connectionWasCancelled)
  }

  private func makeCoordinator(
    _ harness: FailureHarness
  ) -> HomeAssistantConnectionCoordinator {
    HomeAssistantConnectionCoordinator(
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: QueueHomeAssistantLoader(),
        now: { Date(timeIntervalSince1970: 20_000) }
      ),
      browser: StubHomeAssistantWebAuthenticator(),
      session: harness.session,
      supervisor: harness.supervisor
    )
  }

  private func assertCredentialFailure(_ task: Task<Void, any Error>) async {
    do {
      try await task.value
      XCTFail("Expected credential persistence to fail.")
    } catch HomeAssistantCredentialStoreError.keychainFailure {
    } catch {
      XCTFail("Unexpected failure: \(error)")
    }
  }
}

private struct FailureHarness {
  let store: ControllablyFailingCredentialStore
  let session: HomeAssistantSession
  let credentials: HomeAssistantCredentials
  let connection: ScriptedHomeAssistantConnection
  let replacementConnection: ScriptedHomeAssistantConnection
  let connector: ScriptedHomeAssistantConnector
  let supervisor: HomeAssistantConnectionSupervisor
  let probe: AsyncThrowingStreamTestProbe<HomeAssistantStateUpdate>
}

private actor ControllablyFailingCredentialStore: HomeAssistantCredentialStoring {
  enum Operation {
    case load
    case save
    case delete
  }

  private var credentials: HomeAssistantCredentials?
  private var failingOperation: Operation?
  private var blockedDelete: CheckedContinuation<Void, Never>?
  private var blockedDeleteShouldThrow = false
  nonisolated let deleteStarted = XCTestExpectation(description: "Credential delete started")

  func failNext(_ operation: Operation) {
    failingOperation = operation
  }

  func blockNextDelete() {
    blockedDeleteShouldThrow = true
  }

  func finishBlockedDelete(throwing: Bool) {
    blockedDeleteShouldThrow = throwing
    blockedDelete?.resume()
    blockedDelete = nil
  }

  func load() throws -> HomeAssistantCredentials? {
    try failIfNeeded(.load)
    return credentials
  }

  func save(_ credentials: HomeAssistantCredentials) throws {
    try failIfNeeded(.save)
    self.credentials = credentials
  }

  func replace(
    _ credentials: HomeAssistantCredentials?,
    ifCurrentIs original: HomeAssistantCredentials?
  ) throws -> Bool {
    guard self.credentials == original else { return false }
    self.credentials = credentials
    return true
  }

  func delete() async throws {
    if blockedDeleteShouldThrow {
      deleteStarted.fulfill()
      await withCheckedContinuation { blockedDelete = $0 }
      if blockedDeleteShouldThrow {
        blockedDeleteShouldThrow = false
        throw HomeAssistantCredentialStoreError.keychainFailure(-1)
      }
    }
    try failIfNeeded(.delete)
    credentials = nil
  }

  private func failIfNeeded(_ operation: Operation) throws {
    guard failingOperation == operation else { return }
    failingOperation = nil
    throw HomeAssistantCredentialStoreError.keychainFailure(-1)
  }
}

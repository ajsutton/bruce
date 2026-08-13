import XCTest

@testable import Bruce

final class HomeAssistantDisconnectConcurrencyTests: XCTestCase {
  @MainActor
  func testCoordinatorGatesRequestsBeforeBlockedSupervisorStop() async throws {
    let fixture = CoordinatorFixture()
    let apiLoader = BlockingHomeAssistantLoader()
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: fixture.authenticationClient,
      loader: apiLoader,
      now: { [now = fixture.now] in now }
    )
    try await session.install(fixture.existingCredentials())
    let supervisor = RecordingConnectionSupervisor(blocksStop: true)
    let coordinator = HomeAssistantConnectionCoordinator(
      authenticationClient: fixture.authenticationClient,
      browser: fixture.browser,
      session: session,
      supervisor: supervisor
    )
    let disconnect = Task { try await coordinator.disconnect() }
    await fulfillment(of: [supervisor.stopStarted], timeout: 1)

    do {
      _ = try await session.authenticatedGET(path: "api/")
      XCTFail("Expected disconnect boundary to reject the request.")
    } catch HomeAssistantAPIError.noCredentials {
    }
    XCTAssertTrue(apiLoader.requests.isEmpty)

    supervisor.completeStop()
    try await disconnect.value
  }

  func testDisconnectCancelsRequestBeforeBlockedCredentialDeletionCompletes() async throws {
    let fixture = SessionFixture()
    let store = BlockingDeleteCredentialStore()
    let apiLoader = BlockingHomeAssistantLoader()
    let session = makeSession(fixture: fixture, store: store, loader: apiLoader)
    try await session.install(fixture.credentials())
    let read = Task { try await session.authenticatedGET(path: "api/") }
    await fulfillment(of: [apiLoader.started], timeout: 1)

    let disconnect = Task { try await session.disconnect() }
    await fulfillment(of: [store.deleteStarted], timeout: 1)
    XCTAssertTrue(apiLoader.wasCancelled)

    await store.completeDelete()
    try await disconnect.value
    await assertCancellation(read)
  }

  func testDisconnectCancelsRefreshBeforeBlockedCredentialDeletionCompletes() async throws {
    let fixture = SessionFixture()
    let store = BlockingDeleteCredentialStore()
    let refreshLoader = BlockingHomeAssistantLoader()
    let session = HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: refreshLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now }
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))
    let read = Task { try await session.authenticatedGET(path: "api/") }
    await fulfillment(of: [refreshLoader.started], timeout: 1)

    let disconnect = Task { try await session.disconnect() }
    await fulfillment(of: [store.deleteStarted], timeout: 1)
    XCTAssertTrue(refreshLoader.wasCancelled)

    await store.completeDelete()
    try await disconnect.value
    await assertCancellation(read)
  }

  func testRequestStartedDuringCredentialDeletionNeverOpensTransport() async throws {
    let fixture = SessionFixture()
    let store = BlockingDeleteCredentialStore()
    let apiLoader = BlockingHomeAssistantLoader()
    let session = makeSession(fixture: fixture, store: store, loader: apiLoader)
    try await session.install(fixture.credentials())
    let disconnect = Task { try await session.disconnect() }
    await fulfillment(of: [store.deleteStarted], timeout: 1)

    do {
      _ = try await session.authenticatedGET(path: "api/")
      XCTFail("Expected disconnecting session to reject new requests.")
    } catch HomeAssistantAPIError.noCredentials {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(apiLoader.requests.isEmpty)

    await store.completeDelete()
    try await disconnect.value
  }

  private func makeSession(
    fixture: SessionFixture,
    store: BlockingDeleteCredentialStore,
    loader: BlockingHomeAssistantLoader
  ) -> HomeAssistantSession {
    HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: loader,
      now: { [now = fixture.now] in now }
    )
  }

  private func assertCancellation(
    _ task: Task<Data, any Error>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      _ = try await task.value
      XCTFail("Expected cancellation.", file: file, line: line)
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
  }
}

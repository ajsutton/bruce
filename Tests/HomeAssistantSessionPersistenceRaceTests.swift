import XCTest

@testable import Bruce

final class HomeAssistantSessionPersistenceRaceTests: XCTestCase {
  func testReplacementIntentRollsBackRouteWriteThatAlreadyMutatedPersistence() async throws {
    let fixture = SessionFixture()
    let store = BlockingConditionalWriteCredentialStore()
    let replacementQueued = expectation(description: "Replacement queued")
    let gate = HomeAssistantPersistenceGate(waiterQueued: replacementQueued.fulfill)
    let session = makeSession(fixture: fixture, store: store, gate: gate)
    let credentials = fixture.credentials()
    try await session.install(credentials)
    let snapshot = await session.connectionSnapshot()
    let operationEpoch = await session.authenticationOperationEpoch
    let externalURL = fixture.externalURL
    let replacementCredentials = replacementCredentials(credentials)
    await store.blockNextReplace()

    let routeWrite = Task {
      try await session.rememberSuccessful(
        externalURL,
        original: credentials,
        generation: snapshot.persistenceGeneration,
        authenticationSessionEpoch: snapshot.authenticationSessionEpoch,
        authenticationOperationEpoch: operationEpoch
      )
    }
    await fulfillment(of: [store.replaceMutated], timeout: 1)
    let replacement = Task { try await session.install(replacementCredentials) }
    await fulfillment(of: [replacementQueued], timeout: 1)
    replacement.cancel()
    await store.completeReplace()

    await assertStale(routeWrite)
    await assertCancelled(replacement)
    let storedCredentials = await store.storedValue()
    XCTAssertEqual(storedCredentials, credentials)
  }

  func testReplacementIntentRollsBackRefreshThatAlreadyMutatedPersistence() async throws {
    let fixture = SessionFixture()
    let store = BlockingConditionalWriteCredentialStore()
    let refreshLoader = BlockingHomeAssistantLoader()
    let replacementQueued = expectation(description: "Replacement queued")
    let gate = HomeAssistantPersistenceGate(waiterQueued: replacementQueued.fulfill)
    let session = makeSession(
      fixture: fixture,
      store: store,
      gate: gate,
      authenticationLoader: refreshLoader
    )
    let credentials = fixture.credentials(expiresAt: fixture.past)
    let replacementCredentials = replacementCredentials(credentials)
    try await session.install(credentials)
    await store.blockNextReplace()

    let refresh = Task { try await session.refreshIfNeeded(force: true) }
    await fulfillment(of: [refreshLoader.started], timeout: 1)
    refreshLoader.succeed(with: refreshedToken(), statusCode: 200)
    await fulfillment(of: [store.replaceMutated], timeout: 1)
    let replacement = Task { try await session.install(replacementCredentials) }
    await fulfillment(of: [replacementQueued], timeout: 1)
    replacement.cancel()
    await store.completeReplace()

    await assertStale(refresh)
    await assertCancelled(replacement)
    let storedCredentials = await store.storedValue()
    XCTAssertEqual(storedCredentials, credentials)
  }

  private func makeSession(
    fixture: SessionFixture,
    store: BlockingConditionalWriteCredentialStore,
    gate: HomeAssistantPersistenceGate,
    authenticationLoader: any HomeAssistantHTTPDataLoading = QueueHomeAssistantLoader()
  ) -> HomeAssistantSession {
    HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now },
      persistenceGate: gate
    )
  }

  private func replacementCredentials(
    _ credentials: HomeAssistantCredentials
  ) -> HomeAssistantCredentials {
    var replacement = credentials
    replacement.accessToken = "replacement"
    return replacement
  }

  private func refreshedToken() -> Data {
    Data(#"{"access_token":"refreshed","token_type":"Bearer","expires_in":1800}"#.utf8)
  }

  private func assertStale(_ task: Task<Void, any Error>) async {
    do {
      try await task.value
      XCTFail("Expected stale operation.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func assertCancelled(_ task: Task<Void, any Error>) async {
    do {
      try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}

private actor BlockingConditionalWriteCredentialStore: HomeAssistantCredentialStoring {
  nonisolated let replaceMutated = XCTestExpectation(description: "Replace mutated persistence")
  private var value: HomeAssistantCredentials?
  private var shouldBlockNextReplace = false
  private var replaceContinuation: CheckedContinuation<Void, Never>?

  func load() -> HomeAssistantCredentials? { value }

  func save(_ credentials: HomeAssistantCredentials) { value = credentials }

  func replace(
    _ credentials: HomeAssistantCredentials?,
    ifCurrentIs original: HomeAssistantCredentials?
  ) async -> Bool {
    guard value == original else { return false }
    value = credentials
    guard shouldBlockNextReplace else { return true }
    shouldBlockNextReplace = false
    await withCheckedContinuation { continuation in
      replaceContinuation = continuation
      replaceMutated.fulfill()
    }
    return true
  }

  func delete() { value = nil }

  func blockNextReplace() { shouldBlockNextReplace = true }

  func completeReplace() {
    replaceContinuation?.resume()
    replaceContinuation = nil
  }

  func storedValue() -> HomeAssistantCredentials? { value }
}

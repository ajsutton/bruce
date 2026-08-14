import XCTest

@testable import Bruce

final class HASessionRejectionPersistenceTests: XCTestCase {
  func testFailedCredentialRemovalIsSharedAsStale() async throws {
    let fixture = SessionFixture()
    let store = FailingCredentialRejectionStore()
    let refreshLoader = BlockingHomeAssistantLoader()
    let bothRefreshWaiters = expectation(description: "Both refresh waiters registered")
    let bothRejectionWaiters = expectation(description: "Both rejection waiters registered")
    let session = makeSession(
      fixture: fixture,
      store: store,
      refreshLoader: refreshLoader,
      refreshWaiterRegistered: expectation(for: bothRefreshWaiters),
      rejectionWaiterRegistered: expectation(for: bothRejectionWaiters)
    )
    let credentials = fixture.credentials(expiresAt: fixture.past)
    try await session.install(credentials)

    let first = TaskResultProbe<Data>(description: "First read completed")
    let second = TaskResultProbe<Data>(description: "Second read completed")
    _ = readTask(session: session, path: "api/first", probe: first)
    _ = readTask(session: session, path: "api/second", probe: second)
    await fulfillment(of: [bothRefreshWaiters, refreshLoader.started], timeout: 1)
    rejectRefresh(using: refreshLoader)
    await fulfillment(of: [store.replacementStarted, bothRejectionWaiters], timeout: 1)
    await store.failReplacement()

    await assertStale(first)
    await assertStale(second)
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await store.storedValue()
    XCTAssertEqual(currentCredentials, credentials)
    XCTAssertEqual(storedCredentials, credentials)
  }

  func testCancellingOneWaiterDoesNotCancelSharedCredentialRemoval() async throws {
    let fixture = SessionFixture()
    let store = BlockingCredentialRejectionStore()
    let refreshLoader = BlockingHomeAssistantLoader()
    let bothRefreshWaiters = expectation(description: "Both refresh waiters registered")
    let bothRejectionWaiters = expectation(description: "Both rejection waiters registered")
    let session = makeSession(
      fixture: fixture,
      store: store,
      refreshLoader: refreshLoader,
      refreshWaiterRegistered: expectation(for: bothRefreshWaiters),
      rejectionWaiterRegistered: expectation(for: bothRejectionWaiters)
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))
    await store.blockNextReplacement()

    let first = TaskResultProbe<Data>(description: "First read completed")
    let second = TaskResultProbe<Data>(description: "Second read completed")
    let firstTask = readTask(session: session, path: "api/first", probe: first)
    _ = readTask(session: session, path: "api/second", probe: second)
    await fulfillment(of: [bothRefreshWaiters, refreshLoader.started], timeout: 1)
    rejectRefresh(using: refreshLoader)
    await fulfillment(of: [store.replacementStarted, bothRejectionWaiters], timeout: 1)

    firstTask.cancel()
    await assertCancelled(first)
    await store.completeReplacement()

    await assertReauthenticationRequired(second)
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await store.storedValue()
    XCTAssertNil(currentCredentials)
    XCTAssertNil(storedCredentials)
  }

  func testLateWaiterJoinsCredentialRemovalAfterEarlierWaiterCancels() async throws {
    let fixture = SessionFixture()
    let store = BlockingCredentialRejectionStore()
    let session = makeSession(
      fixture: fixture,
      store: store,
      refreshLoader: BlockingHomeAssistantLoader(),
      refreshWaiterRegistered: { _ in },
      rejectionWaiterRegistered: { _ in }
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))
    await store.blockNextReplacement()
    let firstCompletion = TaskResultProbe<Void>(description: "First rejection waiter completed")
    let first = rejectionTask(session: session, probe: firstCompletion)
    await fulfillment(of: [store.replacementStarted], timeout: 1)

    first.cancel()
    await assertCancelled(firstCompletion)
    let lateCompletion = TaskResultProbe<Void>(description: "Late rejection waiter completed")
    _ = rejectionTask(session: session, probe: lateCompletion)
    await store.completeReplacement()

    await assertReauthenticationRequired(lateCompletion)
    let currentCredentials = await session.currentCredentials()
    XCTAssertNil(currentCredentials)
  }

  func testInstallingCredentialsWaitsForBlockedSharedRejection() async throws {
    let fixture = SessionFixture()
    let store = BlockingCredentialRejectionStore()
    let refreshLoader = BlockingHomeAssistantLoader()
    let bothRefreshWaiters = expectation(description: "Both refresh waiters registered")
    let bothRejectionWaiters = expectation(description: "Both rejection waiters registered")
    let session = makeSession(
      fixture: fixture,
      store: store,
      refreshLoader: refreshLoader,
      refreshWaiterRegistered: expectation(for: bothRefreshWaiters),
      rejectionWaiterRegistered: expectation(for: bothRejectionWaiters)
    )
    let credentials = fixture.credentials(expiresAt: fixture.past)
    try await session.install(credentials)
    await store.blockNextReplacement()

    let first = TaskResultProbe<Data>(description: "First read completed")
    let second = TaskResultProbe<Data>(description: "Second read completed")
    _ = readTask(session: session, path: "api/first", probe: first)
    _ = readTask(session: session, path: "api/second", probe: second)
    await fulfillment(of: [bothRefreshWaiters, refreshLoader.started], timeout: 1)
    rejectRefresh(using: refreshLoader)
    await fulfillment(of: [store.replacementStarted, bothRejectionWaiters], timeout: 1)

    var replacement = credentials
    replacement.accessToken = "replacement-access"
    replacement.refreshToken = "replacement-refresh"
    let install = Task { [replacement] in try await session.install(replacement) }
    await store.completeReplacement()
    await assertReauthenticationRequired(first)
    await assertReauthenticationRequired(second)
    try await install.value

    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await store.storedValue()
    XCTAssertEqual(currentCredentials, replacement)
    XCTAssertEqual(storedCredentials, replacement)
  }

  func makeSession(
    fixture: SessionFixture,
    store: any HomeAssistantCredentialStoring,
    refreshLoader: BlockingHomeAssistantLoader,
    persistenceGate: HomeAssistantPersistenceGate = HomeAssistantPersistenceGate(),
    refreshWaiterRegistered: @escaping @Sendable (Int) -> Void,
    rejectionWaiterRegistered: @escaping @Sendable (Int) -> Void
  ) -> HomeAssistantSession {
    HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: refreshLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now },
      persistenceGate: persistenceGate,
      refreshWaiterRegistered: refreshWaiterRegistered,
      rejectionWaiterRegistered: rejectionWaiterRegistered
    )
  }

  func expectation(
    for expectation: XCTestExpectation
  ) -> @Sendable (Int) -> Void {
    { count in
      if count == 2 {
        expectation.fulfill()
      }
    }
  }

  private func rejectRefresh(using loader: BlockingHomeAssistantLoader) {
    loader.succeed(with: Data(#"{"error":"invalid_grant"}"#.utf8), statusCode: 400)
  }

  private func readTask(
    session: HomeAssistantSession,
    path: String,
    probe: TaskResultProbe<Data>
  ) -> Task<Void, Never> {
    Task {
      do {
        await probe.record(.success(try await session.authenticatedGET(path: path)))
      } catch {
        await probe.record(.failure(error))
      }
    }
  }

  func rejectionTask(
    session: HomeAssistantSession,
    probe: TaskResultProbe<Void>
  ) -> Task<Void, Never> {
    Task {
      do {
        try await session.rejectCredentials(generation: 1)
      } catch {
        await probe.record(.failure(error))
      }
    }
  }

  func installTask(
    session: HomeAssistantSession,
    credentials: HomeAssistantCredentials,
    probe: TaskResultProbe<Void>
  ) -> Task<Void, Never> {
    Task {
      do {
        try await session.install(credentials)
        await probe.record(.success(()))
      } catch {
        await probe.record(.failure(error))
      }
    }
  }

  func restoreTask(
    session: HomeAssistantSession,
    probe: TaskResultProbe<Bool>
  ) -> Task<Void, Never> {
    Task {
      do {
        await probe.record(.success(try await session.restore()))
      } catch {
        await probe.record(.failure(error))
      }
    }
  }

  func assertCancelled<Value>(_ probe: TaskResultProbe<Value>) async {
    await fulfillment(of: [probe.completed], timeout: 1)
    guard let result = await probe.recordedResult() else { return }
    guard case .failure(let error) = result else {
      XCTFail("Expected cancellation.")
      return
    }
    if !(error is CancellationError) {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func assertReauthenticationRequired<Value>(_ probe: TaskResultProbe<Value>) async {
    await fulfillment(of: [probe.completed], timeout: 1)
    guard let result = await probe.recordedResult() else { return }
    guard case .failure(let error) = result else {
      XCTFail("Expected reauthentication.")
      return
    }
    if case HomeAssistantAPIError.reauthenticationRequired = error {
    } else {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func assertStale<Value>(_ probe: TaskResultProbe<Value>) async {
    await fulfillment(of: [probe.completed], timeout: 1)
    guard let result = await probe.recordedResult() else { return }
    guard case .failure(let error) = result else {
      XCTFail("Expected stale operation.")
      return
    }
    if case HomeAssistantAPIError.staleOperation = error {
    } else {
      XCTFail("Unexpected error: \(error)")
    }
  }

}

actor BlockingCredentialRejectionStore: HomeAssistantCredentialStoring {
  nonisolated let replacementStarted = XCTestExpectation(
    description: "Credential replacement started"
  )

  private var value: HomeAssistantCredentials?
  private var shouldBlockNextReplacement = false
  private var shouldFailNextSave = false
  private var replacementContinuation: CheckedContinuation<Void, Never>?
  private var shouldCompleteReplacement = false

  func load() -> HomeAssistantCredentials? { value }

  func save(_ credentials: HomeAssistantCredentials) throws {
    if shouldFailNextSave {
      shouldFailNextSave = false
      throw RejectionPersistenceTestError.failure
    }
    value = credentials
  }

  func replace(
    _ credentials: HomeAssistantCredentials?,
    ifCurrentIs original: HomeAssistantCredentials?
  ) async -> Bool {
    guard value == original else { return false }
    value = credentials
    guard shouldBlockNextReplacement else { return true }
    shouldBlockNextReplacement = false
    replacementStarted.fulfill()
    if shouldCompleteReplacement {
      shouldCompleteReplacement = false
      return true
    }
    await withCheckedContinuation { continuation in
      replacementContinuation = continuation
    }
    return true
  }

  func delete() { value = nil }

  func blockNextReplacement() { shouldBlockNextReplacement = true }

  func failNextSave() { shouldFailNextSave = true }

  func completeReplacement() {
    if let replacementContinuation {
      replacementContinuation.resume()
      self.replacementContinuation = nil
    } else {
      shouldCompleteReplacement = true
    }
  }

  func storedValue() -> HomeAssistantCredentials? { value }
}

actor ExternallyDeletedCredentialStore: HomeAssistantCredentialStoring {
  private var value: HomeAssistantCredentials?

  func load() -> HomeAssistantCredentials? { value }

  func save(_ credentials: HomeAssistantCredentials) { value = credentials }

  func replace(
    _ credentials: HomeAssistantCredentials?,
    ifCurrentIs original: HomeAssistantCredentials?
  ) -> Bool {
    guard value == original else { return false }
    value = credentials
    return true
  }

  func delete() { value = nil }

  func deleteExternally() { value = nil }
}

enum RejectionPersistenceTestError: Error {
  case failure
}

private actor FailingCredentialRejectionStore: HomeAssistantCredentialStoring {
  nonisolated let replacementStarted = XCTestExpectation(
    description: "Credential replacement started"
  )

  private var value: HomeAssistantCredentials?
  private var replacementContinuation: CheckedContinuation<Void, Never>?
  private var shouldFailReplacement = false

  func load() -> HomeAssistantCredentials? { value }

  func save(_ credentials: HomeAssistantCredentials) { value = credentials }

  func replace(
    _ credentials: HomeAssistantCredentials?,
    ifCurrentIs original: HomeAssistantCredentials?
  ) async -> Bool {
    guard value == original, credentials == nil else { return false }
    replacementStarted.fulfill()
    if shouldFailReplacement {
      shouldFailReplacement = false
      return false
    }
    await withCheckedContinuation { continuation in
      replacementContinuation = continuation
    }
    return false
  }

  func delete() { value = nil }

  func failReplacement() {
    if let replacementContinuation {
      replacementContinuation.resume()
      self.replacementContinuation = nil
    } else {
      shouldFailReplacement = true
    }
  }

  func storedValue() -> HomeAssistantCredentials? { value }
}

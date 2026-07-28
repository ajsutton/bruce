import XCTest

@testable import Bruce

final class HASessionLifecycleTests: XCTestCase {
  func testPersistenceGateSerializesCredentialWrites() async {
    let gate = HomeAssistantPersistenceGate()
    let firstAcquired = expectation(description: "First write acquired persistence")
    let secondAttempted = expectation(description: "Second write attempted persistence")
    let secondAcquired = expectation(description: "Second write acquired persistence")
    let recorder = PersistenceOrderRecorder()
    let first = Task {
      try await gate.acquire()
      await recorder.append("first")
      firstAcquired.fulfill()
    }
    await fulfillment(of: [firstAcquired], timeout: 1)
    let second = Task {
      secondAttempted.fulfill()
      try await gate.acquire()
      await recorder.append("second")
      secondAcquired.fulfill()
    }
    await fulfillment(of: [secondAttempted], timeout: 1)

    let valuesBeforeRelease = await recorder.values
    XCTAssertEqual(valuesBeforeRelease, ["first"])
    await gate.release()
    await fulfillment(of: [secondAcquired], timeout: 1)
    let valuesAfterRelease = await recorder.values
    XCTAssertEqual(valuesAfterRelease, ["first", "second"])

    await gate.release()
    _ = await (first.result, second.result)
  }

  func testCancelledResumedWaiterTransfersPersistenceGateToNextWaiter() async throws {
    let cancellationDeferral = PersistenceCancellationDeferral()
    let queueObserver = PersistenceWaiterQueueObserver()
    let gate = HomeAssistantPersistenceGate(
      waiterQueued: {
        queueObserver.didQueue()
      },
      cancellationDeferral: {
        await cancellationDeferral.wait()
      }
    )
    try await gate.acquire()
    let cancelledOperationRan = expectation(description: "Cancelled operation did not run")
    cancelledOperationRan.isInverted = true
    let cancelled = Task {
      try await withHomeAssistantPersistence(gate: gate) {
        cancelledOperationRan.fulfill()
      }
    }
    await fulfillment(of: [queueObserver.firstQueued], timeout: 1)
    let nextAcquired = expectation(description: "Next waiter acquired persistence")
    let next = Task {
      try await withHomeAssistantPersistence(gate: gate) {
        nextAcquired.fulfill()
      }
    }
    await fulfillment(of: [queueObserver.secondQueued], timeout: 1)

    cancelled.cancel()
    await fulfillment(of: [cancellationDeferral.started], timeout: 1)
    await gate.release()

    await fulfillment(of: [nextAcquired, cancelledOperationRan], timeout: 1)
    do {
      try await cancelled.value
      XCTFail("Expected persistence waiter cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    try await next.value
    await cancellationDeferral.proceed()
  }

  func testValueEqualInstallMakesAnOlderReadStale() async throws {
    let fixture = SessionFixture()
    let apiLoader = BlockingHomeAssistantLoader()
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: apiLoader,
      now: { [now = fixture.now] in now }
    )
    let credentials = fixture.credentials()
    try await session.install(credentials)
    let read = Task {
      try await session.authenticatedGET(path: "api/")
    }
    await fulfillment(of: [apiLoader.started], timeout: 1)

    try await session.install(credentials)
    apiLoader.succeed(with: Data("stale".utf8), statusCode: 200)

    do {
      _ = try await read.value
      XCTFail("Expected the older read to be rejected.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testValueEqualTokenReplacementMakesOlderWebSocketAccessStale() async throws {
    let fixture = SessionFixture()
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now }
    )
    let credentials = fixture.credentials()
    try await session.install(credentials)
    let access = try await session.authenticatedWebSocketAccess()

    try await session.install(credentials)

    do {
      try await session.rememberSuccessfulWebSocketAccess(access)
      XCTFail("Expected the older WebSocket access to be rejected.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testLateRestoreCannotReplaceNewCredentials() async throws {
    let fixture = SessionFixture()
    let original = fixture.credentials()
    let store = BlockingLoadCredentialStore(value: original)
    let installQueued = expectation(description: "Install queued behind restore")
    let persistenceGate = HomeAssistantPersistenceGate {
      installQueued.fulfill()
    }
    let session = HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now },
      persistenceGate: persistenceGate
    )
    let restore = Task {
      try await session.restore()
    }
    await fulfillment(of: [store.loadStarted], timeout: 1)
    var replacement = original
    replacement.accessToken = "replacement"

    let install = Task { [replacement] in
      try await session.install(replacement)
      return replacement
    }
    await fulfillment(of: [installQueued], timeout: 1)
    await store.completeLoad()

    do {
      _ = try await restore.value
      XCTFail("Expected the late restore to be rejected.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let installedReplacement = try await install.value
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await store.storedValue()
    XCTAssertEqual(currentCredentials, installedReplacement)
    XCTAssertEqual(storedCredentials, installedReplacement)
  }

  func testCancelledRestoreDoesNotInstallLoadedCredentials() async throws {
    let fixture = SessionFixture()
    let original = fixture.credentials()
    let store = BlockingLoadCredentialStore(value: original)
    let session = HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now }
    )
    let restore = Task {
      try await session.restore()
    }
    await fulfillment(of: [store.loadStarted], timeout: 1)

    restore.cancel()
    await store.completeLoad()

    do {
      _ = try await restore.value
      XCTFail("Expected restore cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let currentCredentials = await session.currentCredentials()
    XCTAssertNil(currentCredentials)
  }

  func testCancelledVerificationDoesNotInstallCredentialsWhenLoaderFinishesLate() async throws {
    let fixture = SessionFixture()
    let apiLoader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: apiLoader,
      now: { [now = fixture.now] in now }
    )
    let verification = Task {
      try await session.verifyAndInstall(fixture.credentials()) { data in
        _ = try HomeAssistantAPIClient.status(from: data)
      }
    }
    await fulfillment(of: [apiLoader.started], timeout: 1)

    verification.cancel()
    apiLoader.succeed(with: Data(#"{"message":"API running."}"#.utf8), statusCode: 200)

    do {
      try await verification.value
      XCTFail("Expected verification cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertNil(currentCredentials)
    XCTAssertNil(storedCredentials)
    XCTAssertTrue(apiLoader.wasCancelled)
  }

}

private actor PersistenceOrderRecorder {
  private(set) var values: [String] = []

  func append(_ value: String) {
    values.append(value)
  }
}

private actor PersistenceCancellationDeferral {
  nonisolated let started = XCTestExpectation(description: "Persistence cancellation was deferred")
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    started.fulfill()
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func proceed() {
    continuation?.resume()
    continuation = nil
  }
}

private final class PersistenceWaiterQueueObserver: @unchecked Sendable {
  let firstQueued = XCTestExpectation(description: "First persistence waiter queued")
  let secondQueued = XCTestExpectation(description: "Second persistence waiter queued")
  private let lock = NSLock()
  private var count = 0

  func didQueue() {
    let queuedCount = lock.withLock {
      count += 1
      return count
    }
    if queuedCount == 1 {
      firstQueued.fulfill()
    } else if queuedCount == 2 {
      secondQueued.fulfill()
    }
  }
}

private actor BlockingLoadCredentialStore: HomeAssistantCredentialStoring {
  nonisolated let loadStarted = XCTestExpectation(description: "Credential load started")
  private var value: HomeAssistantCredentials?
  private var loadContinuation: CheckedContinuation<HomeAssistantCredentials?, Never>?

  init(value: HomeAssistantCredentials?) {
    self.value = value
  }

  func load() async -> HomeAssistantCredentials? {
    loadStarted.fulfill()
    return await withCheckedContinuation { continuation in
      loadContinuation = continuation
    }
  }

  func save(_ credentials: HomeAssistantCredentials) {
    value = credentials
  }

  func delete() {
    value = nil
  }

  func completeLoad() {
    loadContinuation?.resume(returning: value)
    loadContinuation = nil
  }

  func storedValue() -> HomeAssistantCredentials? {
    value
  }
}

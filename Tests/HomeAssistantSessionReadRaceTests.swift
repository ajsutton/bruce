import XCTest

@testable import Bruce

final class HomeAssistantSessionReadRaceTests: XCTestCase {
  func testInstallIntentMakesAnOlderReadStaleBeforePersistenceCompletes() async throws {
    let fixture = SessionFixture()
    let installQueued = expectation(description: "Replacement install queued")
    let persistenceGate = HomeAssistantPersistenceGate {
      installQueued.fulfill()
    }
    let apiLoader = OrderedBlockingHomeAssistantLoader(requestCount: 1)
    defer { apiLoader.cancelAll() }
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: apiLoader,
      now: { [now = fixture.now] in now },
      persistenceGate: persistenceGate
    )
    let credentials = fixture.credentials()
    try await session.install(credentials)
    let read = Task { try await session.authenticatedGET(path: "api/") }
    await fulfillment(of: [apiLoader.started(at: 0)], timeout: 1)

    try await persistenceGate.acquire()
    var replacement = credentials
    replacement.accessToken = "replacement"
    let install = Task { try await session.install(replacement) }
    await fulfillment(of: [installQueued], timeout: 1)
    apiLoader.complete(request: 0, data: Data("stale".utf8), statusCode: 200)

    do {
      _ = try await read.value
      XCTFail("Expected the older read to be rejected once replacement began.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    await persistenceGate.release()
    try await install.value
  }

  func testInstallIntentPreventsOlderUnauthorizedReadFromRefreshing() async throws {
    let fixture = SessionFixture()
    let installQueued = expectation(description: "Replacement install queued")
    let persistenceGate = HomeAssistantPersistenceGate {
      installQueued.fulfill()
    }
    let apiLoader = OrderedBlockingHomeAssistantLoader(requestCount: 1)
    defer { apiLoader.cancelAll() }
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: apiLoader,
      now: { [now = fixture.now] in now },
      persistenceGate: persistenceGate
    )
    let credentials = fixture.credentials()
    try await session.install(credentials)
    let read = Task { try await session.authenticatedGET(path: "api/") }
    await fulfillment(of: [apiLoader.started(at: 0)], timeout: 1)

    try await persistenceGate.acquire()
    var replacement = credentials
    replacement.accessToken = "replacement"
    let install = Task { try await session.install(replacement) }
    await fulfillment(of: [installQueued], timeout: 1)
    apiLoader.complete(request: 0, data: Data(), statusCode: 401)

    do {
      _ = try await read.value
      XCTFail("Expected the older unauthorized read to be rejected.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(fixture.authenticationLoader.requests.isEmpty)
    await persistenceGate.release()
    try await install.value
  }

  func testInstallIntentPreventsOlderWebSocketRejection() async throws {
    let fixture = SessionFixture()
    let installQueued = expectation(description: "Replacement install queued")
    let persistenceGate = HomeAssistantPersistenceGate {
      installQueued.fulfill()
    }
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now },
      persistenceGate: persistenceGate
    )
    let credentials = fixture.credentials()
    try await session.install(credentials)
    let access = try await session.authenticatedWebSocketAccess()

    try await persistenceGate.acquire()
    var replacement = credentials
    replacement.accessToken = "replacement"
    let install = Task { try await session.install(replacement) }
    await fulfillment(of: [installQueued], timeout: 1)

    do {
      try await session.rejectWebSocketAccess(access)
      XCTFail("Expected the older WebSocket rejection to be stale.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    do {
      _ = try await session.authenticatedGET(path: "api/")
      XCTFail("Expected new work to be rejected while replacement is pending.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(fixture.apiLoader.requests.isEmpty)
    let currentCredentials = await session.currentCredentials()
    XCTAssertEqual(currentCredentials, credentials)
    await persistenceGate.release()
    try await install.value
  }

  func testCredentialRejectionIntentMakesOlderReadStale() async throws {
    let fixture = SessionFixture()
    let queue = ReadRacePersistenceQueue()
    let persistenceGate = HomeAssistantPersistenceGate(waiterQueued: queue.didQueue)
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now },
      persistenceGate: persistenceGate
    )
    let credentials = fixture.credentials()
    try await session.install(credentials)
    let snapshot = await session.connectionSnapshot()
    let operationEpoch = await session.authenticationOperationEpoch
    try await persistenceGate.acquire()

    let rejection = Task {
      try await session.rejectCredentials(generation: snapshot.persistenceGeneration)
    }
    await fulfillment(of: [queue.firstQueued], timeout: 1)
    do {
      _ = try await session.authenticatedGET(path: "api/")
      XCTFail("Expected new work to be rejected while rejection is pending.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(fixture.apiLoader.requests.isEmpty)
    do {
      try await session.rememberSuccessful(
        fixture.externalURL,
        original: credentials,
        generation: snapshot.persistenceGeneration,
        authenticationSessionEpoch: snapshot.authenticationSessionEpoch,
        authenticationOperationEpoch: operationEpoch
      )
      XCTFail("Expected the read to be stale after credential rejection.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    await persistenceGate.release()
    do {
      try await rejection.value
    } catch HomeAssistantAPIError.reauthenticationRequired {
    } catch {
      XCTFail("Unexpected rejection error: \(error)")
    }
  }
}

private final class ReadRacePersistenceQueue: @unchecked Sendable {
  let firstQueued = XCTestExpectation(description: "Credential rejection queued")
  private let lock = NSLock()
  private var count = 0

  func didQueue() {
    let position = lock.withLock {
      count += 1
      return count
    }
    if position == 1 {
      firstQueued.fulfill()
    }
  }
}

import XCTest

@testable import Bruce

final class HomeAssistantSessionConcurrencyTests: XCTestCase {
  func testDisconnectCancelsAnActiveAPIRequest() async throws {
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
    try await session.install(fixture.credentials())
    let read = Task {
      try await session.authenticatedGET(path: "api/")
    }
    await fulfillment(of: [apiLoader.started], timeout: 1)

    try await session.disconnect()

    do {
      _ = try await read.value
      XCTFail("Expected request cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(apiLoader.wasCancelled)
  }

  func testDisconnectRejectsLateSuccessFromLoaderThatIgnoresCancellation() async throws {
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
    try await session.install(fixture.credentials())
    let read = Task {
      try await session.authenticatedGET(path: "api/")
    }
    await fulfillment(of: [apiLoader.started], timeout: 1)

    try await session.disconnect()
    apiLoader.succeed(with: Data("late".utf8), statusCode: 200)

    do {
      _ = try await read.value
      XCTFail("Expected request cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(apiLoader.wasCancelled)
  }

  func testConnectionCheckRejectsSuccessAfterValidationCancelsCaller() async throws {
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
    try await session.install(fixture.credentials())
    let taskReference = ConnectionCheckTaskReference()
    let check = Task {
      try await session.checkConnection { _ in
        taskReference.cancel()
      }
    }
    taskReference.task = check
    await fulfillment(of: [apiLoader.started], timeout: 1)

    apiLoader.succeed(with: Data(#"{"message":"API running."}"#.utf8), statusCode: 200)

    do {
      _ = try await check.value
      XCTFail("Expected connection check cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testCredentialsRemainAvailableUntilDisconnectCommits() async throws {
    let fixture = SessionFixture()
    let store = BlockingDeleteCredentialStore()
    let session = HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now }
    )
    try await session.install(fixture.credentials())
    let disconnect = Task {
      try await session.disconnect()
    }
    await fulfillment(of: [store.deleteStarted], timeout: 1)

    let credentialsDuringDelete = await session.currentCredentials()
    XCTAssertEqual(credentialsDuringDelete, fixture.credentials())

    await store.completeDelete()
    try await disconnect.value
    let credentialsAfterDelete = await session.currentCredentials()
    XCTAssertNil(credentialsAfterDelete)
  }

  func testConcurrentFallbackReadsShareTheRecordedExternalRoute() async throws {
    let fixture = SessionFixture()
    let apiLoader = HostRoutingHomeAssistantLoader(
      internalHost: fixture.internalURL.host() ?? "",
      externalData: Data("external".utf8)
    )
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: apiLoader,
      now: { [now = fixture.now] in now }
    )
    try await session.install(fixture.credentials())

    async let first = session.authenticatedGET(path: "api/first")
    async let second = session.authenticatedGET(path: "api/second")
    let results = try await [first, second]

    XCTAssertEqual(results, [Data("external".utf8), Data("external".utf8)])
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertEqual(currentCredentials?.lastSuccessfulURL, fixture.externalURL)
    XCTAssertEqual(storedCredentials?.lastSuccessfulURL, fixture.externalURL)
  }

}

private final class ConnectionCheckTaskReference: @unchecked Sendable {
  private let lock = NSLock()
  private var storedTask: Task<Data, any Error>?

  var task: Task<Data, any Error>? {
    get { lock.withLock { storedTask } }
    set { lock.withLock { storedTask = newValue } }
  }

  func cancel() {
    task?.cancel()
  }
}

actor BlockingDeleteCredentialStore: HomeAssistantCredentialStoring {
  nonisolated let deleteStarted = XCTestExpectation(description: "Credential deletion started")
  private var value: HomeAssistantCredentials?
  private var deleteContinuation: CheckedContinuation<Void, Never>?

  func load() -> HomeAssistantCredentials? {
    value
  }

  func save(_ credentials: HomeAssistantCredentials) {
    value = credentials
  }

  func replace(
    _ credentials: HomeAssistantCredentials?,
    ifCurrentIs original: HomeAssistantCredentials?
  ) -> Bool {
    guard value == original else { return false }
    value = credentials
    return true
  }

  func delete() async {
    deleteStarted.fulfill()
    await withCheckedContinuation { continuation in
      deleteContinuation = continuation
    }
    value = nil
  }

  func completeDelete() {
    deleteContinuation?.resume()
    deleteContinuation = nil
  }
}

private final class HostRoutingHomeAssistantLoader:
  HomeAssistantHTTPDataLoading, @unchecked Sendable
{
  private let internalHost: String
  private let externalData: Data

  init(internalHost: String, externalData: Data) {
    self.internalHost = internalHost
    self.externalData = externalData
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    guard request.url?.host() != internalHost else {
      throw URLError(.cannotConnectToHost)
    }
    let responseURL = request.url ?? URL(fileURLWithPath: "/")
    guard
      let response = HTTPURLResponse(
        url: responseURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return (externalData, response)
  }
}

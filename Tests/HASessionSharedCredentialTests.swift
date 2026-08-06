import XCTest

@testable import Bruce

final class HASessionSharedCredentialTests: XCTestCase {
  func testAppRefreshDoesNotOverwriteCredentialsRotatedByWidget() async throws {
    let fixture = SessionFixture()
    let store = ExternallyReplacingCredentialStore()
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
    let original = fixture.credentials(expiresAt: fixture.past)
    try await session.install(original)
    var widgetRefreshed = original
    widgetRefreshed.accessToken = "widget-refreshed-access"
    widgetRefreshed.refreshToken = "widget-refreshed-refresh"
    await store.replaceBeforeNextConditionalWrite(with: widgetRefreshed)
    let refresh = Task { try await session.refreshIfNeeded(force: true) }
    await fulfillment(of: [refreshLoader.started], timeout: 1)

    refreshLoader.succeed(with: refreshedTokenResponse, statusCode: 200)

    do {
      try await refresh.value
      XCTFail("Expected the app refresh to become stale.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await store.load()
    XCTAssertEqual(currentCredentials, widgetRefreshed)
    XCTAssertEqual(storedCredentials, widgetRefreshed)
  }

  func testNewInstallWinsWhileOldRefreshReconcilesSharedCredentials() async throws {
    let fixture = SessionFixture()
    let store = BlockingReconciliationCredentialStore()
    let refreshLoader = BlockingHomeAssistantLoader()
    let session = makeSession(fixture: fixture, store: store, refreshLoader: refreshLoader)
    let original = fixture.credentials(expiresAt: fixture.past)
    try await session.install(original)
    var widgetRefreshed = original
    widgetRefreshed.accessToken = "widget-refreshed-access"
    await store.replaceBeforeNextConditionalWrite(with: widgetRefreshed)
    await store.blockNextLoad()
    let refresh = Task { try await session.refreshIfNeeded(force: true) }
    await fulfillment(of: [refreshLoader.started], timeout: 1)
    refreshLoader.succeed(with: refreshedTokenResponse, statusCode: 200)
    await fulfillment(of: [store.loadStarted], timeout: 1)
    var newConnection = fixture.credentials()
    newConnection.accessToken = "new-connection-access"
    newConnection.refreshToken = "new-connection-refresh"
    let expectedNewConnection = newConnection

    let install = Task { @Sendable in
      try await session.install(expectedNewConnection)
    }
    await store.completeLoad()

    do {
      try await refresh.value
      XCTFail("Expected the old refresh to become stale.")
    } catch HomeAssistantAPIError.staleOperation {
    }
    try await install.value
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await store.storedValue()
    XCTAssertEqual(currentCredentials, expectedNewConnection)
    XCTAssertEqual(storedCredentials, expectedNewConnection)
  }

  func testCancelledInstallReconcilesCredentialsRotatedByWidget() async throws {
    let fixture = SessionFixture()
    let store = BlockingSaveCredentialStore()
    let session = makeSession(
      fixture: fixture,
      store: store,
      refreshLoader: fixture.authenticationLoader
    )
    let original = fixture.credentials()
    try await session.install(original)
    var candidate = original
    candidate.accessToken = "app-candidate"
    var widgetRefreshed = original
    widgetRefreshed.accessToken = "widget-refreshed"
    await store.blockNextSave()
    let install = Task { try await session.install(candidate) }
    await fulfillment(of: [store.saveStarted], timeout: 1)

    install.cancel()
    await store.completeSave(replacingWith: widgetRefreshed)

    do {
      try await install.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
    }
    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await store.load()
    XCTAssertEqual(currentCredentials, widgetRefreshed)
    XCTAssertEqual(storedCredentials, widgetRefreshed)
  }

  private func makeSession(
    fixture: SessionFixture,
    store: any HomeAssistantCredentialStoring,
    refreshLoader: any HomeAssistantHTTPDataLoading
  ) -> HomeAssistantSession {
    HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: refreshLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now }
    )
  }

  private var refreshedTokenResponse: Data {
    Data(
      """
      {
        "access_token": "refreshed-access",
        "token_type": "Bearer",
        "expires_in": 1800
      }
      """.utf8
    )
  }
}

private actor BlockingReconciliationCredentialStore: HomeAssistantCredentialStoring {
  nonisolated let loadStarted = XCTestExpectation(description: "Reconciliation load started")
  private var value: HomeAssistantCredentials?
  private var externalReplacement: HomeAssistantCredentials?
  private var shouldBlockLoad = false
  private var loadContinuation: CheckedContinuation<Void, Never>?

  func load() async -> HomeAssistantCredentials? {
    guard shouldBlockLoad else { return value }
    shouldBlockLoad = false
    loadStarted.fulfill()
    await withCheckedContinuation { loadContinuation = $0 }
    return value
  }

  func save(_ credentials: HomeAssistantCredentials) { value = credentials }

  func replace(
    _ credentials: HomeAssistantCredentials?,
    ifCurrentIs original: HomeAssistantCredentials?
  ) -> Bool {
    if let externalReplacement {
      value = externalReplacement
      self.externalReplacement = nil
    }
    guard value == original else { return false }
    value = credentials
    return true
  }

  func delete() { value = nil }

  func replaceBeforeNextConditionalWrite(with credentials: HomeAssistantCredentials) {
    externalReplacement = credentials
  }

  func blockNextLoad() { shouldBlockLoad = true }

  func completeLoad() {
    loadContinuation?.resume()
    loadContinuation = nil
  }

  func storedValue() -> HomeAssistantCredentials? { value }
}

private actor BlockingSaveCredentialStore: HomeAssistantCredentialStoring {
  nonisolated let saveStarted = XCTestExpectation(description: "Credential save started")
  private var value: HomeAssistantCredentials?
  private var shouldBlockSave = false
  private var saveContinuation: CheckedContinuation<Void, Never>?

  func load() -> HomeAssistantCredentials? { value }

  func save(_ credentials: HomeAssistantCredentials) async {
    value = credentials
    guard shouldBlockSave else { return }
    shouldBlockSave = false
    saveStarted.fulfill()
    await withCheckedContinuation { saveContinuation = $0 }
  }

  func replace(
    _ credentials: HomeAssistantCredentials?,
    ifCurrentIs original: HomeAssistantCredentials?
  ) -> Bool {
    guard value == original else { return false }
    value = credentials
    return true
  }

  func delete() { value = nil }

  func blockNextSave() { shouldBlockSave = true }

  func completeSave(replacingWith credentials: HomeAssistantCredentials) {
    value = credentials
    saveContinuation?.resume()
    saveContinuation = nil
  }
}

private actor ExternallyReplacingCredentialStore: HomeAssistantCredentialStoring {
  private var value: HomeAssistantCredentials?
  private var externalReplacement: HomeAssistantCredentials?

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
    if let externalReplacement {
      value = externalReplacement
      self.externalReplacement = nil
    }
    guard value == original else { return false }
    value = credentials
    return true
  }

  func delete() {
    value = nil
  }

  func replaceBeforeNextConditionalWrite(with credentials: HomeAssistantCredentials) {
    externalReplacement = credentials
  }
}

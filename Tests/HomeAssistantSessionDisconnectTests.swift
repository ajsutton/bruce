import XCTest

@testable import Bruce

final class HomeAssistantSessionDisconnectTests: XCTestCase {
  func testFailedCredentialDeletionLeavesSessionUsable() async throws {
    let fixture = SessionFixture()
    let store = FailingDeleteCredentialStore()
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

    do {
      try await session.disconnect()
      XCTFail("Expected credential deletion to fail.")
    } catch HomeAssistantCredentialStoreError.keychainFailure {
    } catch {
      XCTFail("Unexpected deletion error: \(error)")
    }

    let credentials = await session.currentCredentials()
    let storedCredentials = await store.load()
    XCTAssertEqual(credentials, fixture.credentials())
    XCTAssertEqual(storedCredentials, fixture.credentials())
  }
}

private actor FailingDeleteCredentialStore: HomeAssistantCredentialStoring {
  private var value: HomeAssistantCredentials?

  func load() -> HomeAssistantCredentials? { value }

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

  func delete() throws {
    throw HomeAssistantCredentialStoreError.keychainFailure(-1)
  }
}

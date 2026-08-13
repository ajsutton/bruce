import XCTest

@testable import Bruce

final class HomeAssistantTokenRouteTests: XCTestCase {
  func testMixedRejectedAndOfflineRefreshRoutesPreserveCredentials() async throws {
    let fixture = SessionFixture()
    fixture.authenticationLoader.results = [
      .success(Data(#"{"error":"invalid_grant"}"#.utf8), statusCode: 400),
      .failure(URLError(.notConnectedToInternet)),
    ]
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { [now = fixture.now] in now }
      ),
      loader: fixture.apiLoader,
      now: { [now = fixture.now] in now }
    )
    let credentials = fixture.credentials(expiresAt: fixture.past)
    try await session.install(credentials)

    do {
      try await session.refreshIfNeeded(force: true)
      XCTFail("Expected refresh to remain offline.")
    } catch {
      XCTAssertTrue(HomeAssistantRequestRouter.isConnectivityFailure(error))
    }

    let currentCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertEqual(currentCredentials, credentials)
    XCTAssertEqual(storedCredentials, credentials)
  }
}

import XCTest

@testable import Bruce

final class HASingleRouteVerificationTests: XCTestCase {
  func testVerificationRejectsIncompatiblePayloadWithoutInstallingCredentials() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(Data("{}".utf8), statusCode: 200)]
    )
    let credentials = HomeAssistantCredentials(
      instanceID: "single-route",
      instanceName: "Single Route Home",
      internalURL: fixture.internalURL,
      externalURL: nil,
      lastSuccessfulURL: fixture.internalURL,
      accessToken: "access-value",
      refreshToken: "refresh-value",
      tokenType: "Bearer",
      accessTokenExpiresAt: fixture.future,
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
    do {
      try await session.verifyAndInstall(credentials) { data in
        _ = try HomeAssistantAPIClient.status(from: data)
      }
      XCTFail("Expected an incompatible server response.")
    } catch HomeAssistantAPIError.incompatibleServer {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let installedCredentials = await session.currentCredentials()
    let storedCredentials = await fixture.store.value
    XCTAssertNil(installedCredentials)
    XCTAssertNil(storedCredentials)
  }
}

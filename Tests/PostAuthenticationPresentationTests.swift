import XCTest

@testable import Bruce

@MainActor
final class PostAuthenticationPresentationTests: XCTestCase {
  func testPostAuthenticationCheckKeepsSetupVisibleAsLoading() {
    let presentation = HomeAssistantPresentation(
      step: .finishingConnection(credentials),
      connectionCheckState: .checking
    )

    XCTAssertEqual(presentation.screen, .setup)
    XCTAssertTrue(presentation.isConnecting)
    XCTAssertEqual(presentation.access, .loading)
    XCTAssertNil(presentation.connectionProblem)
  }

  func testPostAuthenticationFailureKeepsSetupVisibleForRecovery() {
    let presentation = HomeAssistantPresentation(
      step: .connectionFailed(credentials, .networkUnavailable),
      connectionCheckState: .failed(.networkUnavailable)
    )

    XCTAssertEqual(presentation.screen, .setup)
    XCTAssertFalse(presentation.isConnecting)
    XCTAssertEqual(presentation.access, .requiresUserAction)
    XCTAssertNil(presentation.connectionProblem)
  }

  private var credentials: HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(string: "https://home.example") ?? URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

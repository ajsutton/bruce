#if os(macOS)
  import XCTest

  @testable import Bruce

  @MainActor
  final class HomeAssistantMainStatusTests: XCTestCase {
    func testRestoringDoesNotClaimConnectionOrSetupState() {
      let status = HomeAssistantMainStatus(
        step: .restoring,
        connectionCheckState: .idle,
        isDisconnecting: false
      )

      XCTAssertEqual(status.title, "Checking Home Assistant Connection")
      XCTAssertEqual(status.actionTitle, "Open Home Assistant Settings")
    }

    func testConfiguredNetworkFailureIsUnavailableRatherThanConnected() {
      let status = HomeAssistantMainStatus(
        step: .configured(credentials),
        connectionCheckState: .failed(.networkUnavailable),
        isDisconnecting: false
      )

      XCTAssertEqual(status.title, "Home Is Unavailable")
      XCTAssertEqual(status.actionTitle, "Manage Connection")
    }

    func testConfiguredAuthenticationFailureRequestsSignIn() {
      let status = HomeAssistantMainStatus(
        step: .configured(credentials),
        connectionCheckState: .reauthenticationRequired,
        isDisconnecting: false
      )

      XCTAssertEqual(status.title, "Sign In to Home Again")
      XCTAssertEqual(status.actionTitle, "Manage Connection")
    }

    func testDisconnectingOverridesThePreviousConnectionStatus() {
      let status = HomeAssistantMainStatus(
        step: .connected(credentials),
        connectionCheckState: .succeeded,
        isDisconnecting: true
      )

      XCTAssertEqual(status.title, "Disconnecting from Home Assistant")
    }

    func testSettingsNavigationStartsOnGeneralAndRoutesToHomeAssistant() {
      let navigation = BruceSettingsNavigation()
      XCTAssertEqual(navigation.selectedSection, .general)

      navigation.showHomeAssistant()

      XCTAssertEqual(navigation.selectedSection, .homeAssistant)
    }

    private var credentials: HomeAssistantCredentials {
      HomeAssistantCredentials(
        instanceID: "home",
        instanceName: "Home",
        internalURL: URL(string: "http://home.local:8123"),
        externalURL: URL(string: "https://home.example"),
        lastSuccessfulURL: URL(string: "https://home.example")
          ?? URL(fileURLWithPath: "/"),
        accessToken: "access",
        refreshToken: "refresh",
        tokenType: "Bearer",
        accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
        clientID: HomeAssistantOAuthConfiguration.release.clientID
      )
    }
  }
#endif

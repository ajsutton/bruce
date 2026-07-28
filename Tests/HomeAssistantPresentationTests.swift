import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantPresentationTests: XCTestCase {
  func testHealthyConnectionShowsPanelsWithoutAConnectionMessage() {
    let presentation = makePresentation(step: .connected(credentials), state: .succeeded)

    XCTAssertEqual(presentation.screen, .panels)
    XCTAssertFalse(presentation.isConnecting)
    XCTAssertNil(presentation.connectionProblem)
    XCTAssertEqual(presentation.connection, .connected(credentials))
    XCTAssertTrue(presentation.shouldRefresh(when: .active))
    XCTAssertFalse(presentation.shouldRefresh(when: .background))
  }

  func testRestoringShowsPanelLoadingState() {
    let presentation = makePresentation(step: .restoring)

    XCTAssertEqual(presentation.screen, .panels)
    XCTAssertTrue(presentation.isConnecting)
    XCTAssertNil(presentation.connectionProblem)
    XCTAssertEqual(presentation.connection, .connecting)
  }

  func testConfiguredNetworkFailureShowsBannerAndPreservesTemperatures() {
    let presentation = makePresentation(
      step: .configured(credentials),
      state: .failed(.networkUnavailable)
    )

    XCTAssertEqual(presentation.screen, .panels)
    XCTAssertEqual(
      presentation.connectionProblem,
      "Home Assistant can’t be reached. Temperatures may be out of date."
    )
    XCTAssertEqual(presentation.connection, .unavailable)
  }

  func testConnectionCheckUsesProgressWithoutAProblemBanner() {
    let presentation = makePresentation(
      step: .configured(credentials),
      state: .checking
    )

    XCTAssertTrue(presentation.isConnecting)
    XCTAssertNil(presentation.connectionProblem)
  }

  func testDisconnectedSetupDoesNotShowPanels() {
    let presentation = makePresentation(step: .introduction)

    XCTAssertEqual(presentation.screen, .setup)
    XCTAssertEqual(presentation.connection, .disconnected)
    XCTAssertFalse(presentation.shouldRefresh(when: .active))
  }

  private func makePresentation(
    step: HomeAssistantSetupStore.Step,
    state: HomeAssistantSetupStore.ConnectionCheckState = .idle
  ) -> HomeAssistantPresentation {
    HomeAssistantPresentation(
      step: step,
      connectionCheckState: state
    )
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

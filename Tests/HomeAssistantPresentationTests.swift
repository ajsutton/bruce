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
      .unavailable
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

  func testSmartChargingLabelDoesNotImplyTheBatteryIsThePowerSource() {
    let copy = EVChargingCopy(mode: .standard)

    XCTAssertEqual(copy.chargingModeTitle(.smart), "Smart")
    XCTAssertEqual(
      copy.chargingModeDescription(.smart),
      "Charges when the home has energy to spare"
    )
  }

  func testChargingActivityShowsMeasuredPower() {
    let presentation = HomeAssistantEVActivityPresentation(
      activity: .charging(powerWatts: 7_024),
      mode: .standard,
      locale: Locale(identifier: "en_AU")
    )

    XCTAssertEqual(presentation.text, "Charging · 7.0 kW")
    XCTAssertEqual(presentation.icon, "bolt.car.fill")
  }

  func testFullBrucePauseTakesABreather() {
    let presentation = HomeAssistantEVActivityPresentation(
      activity: .paused(reason: .homeBattery),
      mode: .full
    )

    XCTAssertEqual(
      presentation.text,
      "Car charging’s parked — saving the house battery’s bacon"
    )
    XCTAssertEqual(presentation.icon, "pause.circle.fill")
    XCTAssertEqual(
      presentation.accessibilityText,
      "Car charging’s parked — saving the house battery’s bacon"
    )
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

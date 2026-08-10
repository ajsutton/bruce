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
  }

  func testSceneActivationRefreshesLocalPreferences() {
    var refreshedLocalPreferences = false

    HomeAssistantRefreshCoordinator.sceneDidChange(
      to: .active,
      refreshLocalPreferences: { refreshedLocalPreferences = true }
    )

    XCTAssertTrue(refreshedLocalPreferences)
  }

  func testInactiveSceneSuspendsUpdatesByDefault() {
    XCTAssertFalse(
      HomeAssistantRefreshCoordinator.shouldObserveUpdates(
        while: .inactive
      )
    )
  }

  func testActiveSceneObservesUpdates() {
    XCTAssertTrue(
      HomeAssistantRefreshCoordinator.shouldObserveUpdates(
        while: .active
      )
    )
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

  func testChargingDecisionFormatsCompactHeaderMetrics() {
    let presentation = chargingDecisionPresentation(
      desired: true,
      safeMinutes: 108,
      batteryStateOfCharge: 78,
      hour: 10
    )

    XCTAssertEqual(presentation.intent, .allowed)
    XCTAssertEqual(presentation.safeChargingTime, "1h48m")
    XCTAssertEqual(
      presentation.safeChargingTimeAccessibility,
      "1 hour, 48 minutes"
    )
    XCTAssertEqual(presentation.batteryStateOfCharge, "78%")
    XCTAssertEqual(presentation.batteryIcon, "battery.75percent")
  }

  func testChargingDecisionShowsPriceAsTheImmediateSmartChargingBlocker() {
    let presentation = chargingDecisionPresentation(
      desired: false,
      priceAllowsCharging: false,
      price: 0.42,
      hour: 17
    )

    XCTAssertEqual(presentation.explanation, "Price too high · 42¢/kWh")
  }

  func testChargingDecisionExplainsPriceHysteresis() {
    let presentation = chargingDecisionPresentation(
      desired: false,
      priceAllowsCharging: false,
      price: 0.37,
      hour: 10
    )

    XCTAssertEqual(
      presentation.explanation,
      "Waiting for price below 35¢/kWh · now 37¢/kWh"
    )
  }

  func testChargingDecisionExplainsDaytimeBatteryRestartThreshold() {
    let presentation = chargingDecisionPresentation(
      desired: false,
      batteryStateOfCharge: 20,
      hour: 10
    )

    XCTAssertEqual(
      presentation.explanation,
      "Waiting for home battery above 20% · now 20%"
    )
  }

  func testChargingDecisionUsesUpdatedDaytimeBatteryReserve() {
    let presentation = chargingDecisionPresentation(
      desired: true,
      batteryStateOfCharge: 15,
      hour: 10
    )

    XCTAssertEqual(presentation.explanation, "Home battery has enough reserve")
  }

  func testChargingDecisionExplainsUpdatedOvernightBatteryReserve() {
    let presentation = chargingDecisionPresentation(
      desired: false,
      batteryStateOfCharge: 15,
      hour: 22
    )

    XCTAssertEqual(
      presentation.explanation,
      "Protecting the 15% home-battery reserve"
    )
  }

  func testChargingDecisionExplainsOvernightWait() {
    let presentation = chargingDecisionPresentation(
      desired: false,
      safeMinutes: 48,
      batteryStateOfCharge: 78,
      hour: 22
    )

    XCTAssertEqual(
      presentation.explanation,
      "Waiting for the safe overnight start"
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

  private func chargingDecisionPresentation(
    desired: Bool,
    safeMinutes: Double? = 108,
    priceAllowsCharging: Bool = true,
    price: Double = 0.24,
    batteryStateOfCharge: Double? = 78,
    hour: Int
  ) -> EVChargingDecisionPresentation {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    let date =
      calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 4, hour: hour)
      ) ?? Date(timeIntervalSince1970: 0)
    return EVChargingDecisionPresentation(
      decision: HomeAssistantEVChargingDecision(
        isChargingDesired: desired,
        overnightSafeChargingMinutes: safeMinutes,
        priceAllowsCharging: priceAllowsCharging,
        currentPriceDollarsPerKilowattHour: price,
        batteryStateOfCharge: batteryStateOfCharge
      ),
      chargingMode: .smart,
      mode: .standard,
      date: date,
      calendar: calendar,
      locale: Locale(identifier: "en_AU")
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

import XCTest

@testable import Bruce

final class BruceCopyTests: XCTestCase {
  func testStringCatalogEntryResolvesForEachLanguageVariant() {
    let entry = BruceCopy.Entry.localized("app.climateTab")

    XCTAssertEqual(BruceCopy(mode: .standard).text(entry), "Climate")
    XCTAssertEqual(BruceCopy(mode: .full).text(entry), "Air-con")
  }

  func testAppShellUsesFullBruceCopy() {
    let standard = AppCopy(mode: .standard)
    let full = AppCopy(mode: .full)

    XCTAssertNotEqual(standard.climateTab, full.climateTab)
    XCTAssertNotEqual(standard.energyTab, full.energyTab)
    XCTAssertNotEqual(standard.fullBruceFooter, full.fullBruceFooter)
    XCTAssertNotEqual(standard.iconChangeFailedTitle, full.iconChangeFailedTitle)
    XCTAssertNotEqual(standard.notConnectedTitle, full.notConnectedTitle)
    XCTAssertNotEqual(
      HomeAssistantInterfaceCopy(mode: .standard).done,
      HomeAssistantInterfaceCopy(mode: .full).done
    )
  }

  func testEnergyErrorsAndUnavailableStatesUseFullBruceCopy() {
    let standardCharging = EVChargingCopy(mode: .standard)
    let fullCharging = EVChargingCopy(mode: .full)
    let standardHome = HomeEnergyCopy(mode: .standard)
    let fullHome = HomeEnergyCopy(mode: .full)

    XCTAssertNotEqual(standardCharging.unavailable, fullCharging.unavailable)
    XCTAssertNotEqual(
      standardCharging.chargerStatusUnavailable,
      fullCharging.chargerStatusUnavailable
    )
    XCTAssertNotEqual(
      standardCharging.problem(HomeAssistantEVChargingStore.Problem.updateFailed),
      fullCharging.problem(HomeAssistantEVChargingStore.Problem.updateFailed)
    )
    XCTAssertNotEqual(
      standardHome.problem(HomeAssistantHomeEnergyStore.Problem.connectionUnavailable),
      fullHome.problem(HomeAssistantHomeEnergyStore.Problem.connectionUnavailable)
    )
  }

  func testFullBruceStaleEVCopyKeepsItsVoice() {
    let copy = EVChargingCopy(mode: .full)

    XCTAssertEqual(
      copy.lastKnown(copy.chargingModeDescription(.smart)),
      "Last word Bruce got: Charger uses the house’s spare juice. Too easy."
    )
  }

  func testStaleDataLabelsUseTheSelectedVoice() {
    XCTAssertEqual(HomeEnergyCopy(mode: .standard).lastKnown, "Last known")
    XCTAssertEqual(TemperatureCopy(mode: .full).lastKnown, "Last word Bruce got")
  }

  func testLiveServerStatusKeepsContextInItsAccessibilityCopy() {
    let standard = HomeAssistantInterfaceCopy(mode: .standard)
    let full = HomeAssistantInterfaceCopy(mode: .full)

    XCTAssertEqual(standard.serverLive, "Live")
    XCTAssertEqual(standard.serverLiveAccessibility, "Home Assistant is live")
    XCTAssertTrue(full.serverLiveAccessibility.contains("Home Assistant"))
  }

  func testGarageStatusCopyResolvesForEachLanguageVariant() {
    let standard = GarageDoorCopy(mode: .standard)
    let full = GarageDoorCopy(mode: .full)

    XCTAssertEqual(standard.navigationTitle, "Car")
    XCTAssertEqual(standard.doorState(.closed), "Closed")
    XCTAssertEqual(standard.lightOff, "Off")
    XCTAssertEqual(standard.unlocked, "Unlocked")
    XCTAssertEqual(full.navigationTitle, "The Wheels")
    XCTAssertEqual(full.doorState(.closed), "Shut. Good as gold.")
    XCTAssertEqual(full.stopDoor, "Stop the Garage Door")
    XCTAssertNotEqual(standard.noDevicesTitle, full.noDevicesTitle)
  }

  func testClimateErrorsAndAccessibilityCopyUseFullBruceVoice() {
    let standard = TemperatureCopy(mode: .standard)
    let full = TemperatureCopy(mode: .full)

    XCTAssertNotEqual(standard.unavailable, full.unavailable)
    XCTAssertNotEqual(
      standard.problem(HomeAssistantTemperatureStore.Problem.invalidResponse),
      full.problem(HomeAssistantTemperatureStore.Problem.invalidResponse)
    )
    XCTAssertNotEqual(
      standard.turnOn(name: "Living Room"),
      full.turnOn(name: "Living Room")
    )
    XCTAssertTrue(full.turnOn(name: "Living Room").contains("Living Room"))
    XCTAssertTrue(full.powerUnavailable(name: "Living Room").contains("Living Room"))
  }
}

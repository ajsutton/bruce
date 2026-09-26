import XCTest

@testable import Bruce

final class SiriCopyTests: XCTestCase {
  private let locale = Locale(identifier: "en_AU")

  func testPowerResponsesUseSingularAndPluralUnits() {
    let copy = SiriCopy(mode: .standard)

    XCTAssertEqual(copy.solarGeneration(1, locale: locale), "Solar generation is 1 kilowatt.")
    XCTAssertEqual(copy.electricityUsage(2, locale: locale), "The home is using 2 kilowatts.")
  }

  func testFullBruceResponsesRetainReadingMeaningAndUnits() {
    let copy = SiriCopy(mode: .full)

    XCTAssertEqual(
      copy.batteryLevel(76, locale: locale), "The home battery’s got 76 percent in the tank.")
    XCTAssertEqual(
      copy.solarGeneration(2.4, locale: locale), "The solar’s pulling in 2.4 kilowatts. Good stuff."
    )
    XCTAssertEqual(copy.chargerMode(.smart), "EV charger mode: Smart Charging — using spare juice.")
  }

  func testFullBruceErrorsAndChargerStatusUseTheSelectedVoice() {
    let standard = SiriCopy(mode: .standard)
    let full = SiriCopy(mode: .full)

    for error in [
      BruceSiriError.unavailable, .connectionUnavailable, .signInRequired, .modeNotConfirmed,
    ] {
      XCTAssertNotEqual(standard.error(error), full.error(error))
    }
    XCTAssertNotEqual(standard.chargerStatus(.notPluggedIn), full.chargerStatus(.notPluggedIn))
    XCTAssertNotEqual(
      standard.chargerMode(.off, didChange: true), full.chargerMode(.off, didChange: true))
  }
}

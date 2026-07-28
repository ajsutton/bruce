import XCTest

@testable import Bruce

final class HomeAssistantHomeEnergyPresentationTests: XCTestCase {
  private let locale = Locale(identifier: "en_AU")

  func testStandardPresentationUsesPlainEnergyLabels() {
    XCTAssertEqual(
      HomeEnergyMetricPresentation.pv(
        kilowatts: 8.4,
        mode: .standard,
        locale: locale
      ).title,
      "PV generation"
    )
    XCTAssertEqual(
      HomeEnergyMetricPresentation.consumption(
        kilowatts: 3.1,
        mode: .standard,
        locale: locale
      ).title,
      "Usage"
    )
  }

  func testFullBrucePresentationUsesApprovedEnergyLabels() {
    XCTAssertEqual(
      HomeEnergyMetricPresentation.pv(
        kilowatts: 0,
        mode: .full,
        locale: locale
      ).title,
      "Solar PV Is Cranking"
    )
    XCTAssertEqual(
      HomeEnergyMetricPresentation.battery(
        stateOfCharge: 38,
        mode: .full,
        locale: locale
      ).title,
      "Battery Juice Tank"
    )
    XCTAssertEqual(
      HomeEnergyMetricPresentation.consumption(
        kilowatts: 4.6,
        mode: .full,
        locale: locale
      ).title,
      "House Power Chew"
    )
  }

  func testGridPresentationShowsImportAndExportDirection() {
    let importing = HomeEnergyMetricPresentation.grid(
      kilowatts: 3.9,
      mode: .standard,
      locale: locale
    )
    let exporting = HomeEnergyMetricPresentation.grid(
      kilowatts: -2.7,
      mode: .standard,
      locale: locale
    )

    XCTAssertEqual(importing.title, "Grid import")
    XCTAssertEqual(importing.value, "3.9 kW")
    XCTAssertEqual(importing.icon, "arrow.down.left")
    XCTAssertEqual(exporting.title, "Grid export")
    XCTAssertEqual(exporting.value, "2.7 kW")
    XCTAssertEqual(exporting.icon, "arrow.up.right")
  }

  func testGridPresentationTreatsFlowsThatRoundToZeroAsIdle() {
    let idle = HomeEnergyMetricPresentation.grid(
      kilowatts: 0.099,
      mode: .standard,
      locale: locale
    )
    let importing = HomeEnergyMetricPresentation.grid(
      kilowatts: 0.1,
      mode: .standard,
      locale: locale
    )

    XCTAssertEqual(idle.title, "Grid idle")
    XCTAssertEqual(idle.value, "0.0 kW")
    XCTAssertEqual(importing.title, "Grid import")
    XCTAssertEqual(importing.value, "0.1 kW")

    let exporting = HomeEnergyMetricPresentation.grid(
      kilowatts: -0.1,
      mode: .standard,
      locale: locale
    )
    XCTAssertEqual(exporting.title, "Grid export")
    XCTAssertEqual(exporting.value, "0.1 kW")
  }

  func testUnavailablePresentationRetainsFullBruceVoice() {
    XCTAssertEqual(
      HomeEnergyMetricPresentation.pv(
        kilowatts: nil,
        mode: .full,
        locale: locale
      ).title,
      "Solar PV Has Gone Walkabout"
    )
    XCTAssertEqual(
      HomeEnergyMetricPresentation.grid(
        kilowatts: nil,
        mode: .full,
        locale: locale
      ).title,
      "The Grid Mob"
    )
  }
}

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

  func testPricePresentationShowsCurrentCentsRatePerKilowattHour() {
    let general = HomeEnergyMetricPresentation.generalPrice(
      dollarsPerKilowattHour: 0.35,
      mode: .standard,
      locale: locale
    )
    let feedIn = HomeEnergyMetricPresentation.feedInPrice(
      dollarsPerKilowattHour: -0.051,
      mode: .standard,
      locale: locale
    )
    let feedInCredit = HomeEnergyMetricPresentation.feedInPrice(
      dollarsPerKilowattHour: 0.09,
      mode: .standard,
      locale: locale
    )

    XCTAssertEqual(general.title, "General price")
    XCTAssertEqual(general.value, "35¢/kWh")
    XCTAssertEqual(feedIn.title, "Export charge")
    XCTAssertEqual(feedIn.value, "5.1¢/kWh")
    XCTAssertEqual(feedIn.color, .orange)
    XCTAssertEqual(feedInCredit.title, "Feed-in price")
    XCTAssertEqual(feedInCredit.value, "9¢/kWh")
    XCTAssertEqual(feedInCredit.color, .green)
  }

  func testPricePresentationRetainsFullBruceVoiceWhenUnavailable() {
    XCTAssertEqual(
      HomeEnergyMetricPresentation.generalPrice(
        dollarsPerKilowattHour: nil,
        mode: .full,
        locale: locale
      ).title,
      "Power Price Has Gone Walkabout"
    )
    XCTAssertEqual(
      HomeEnergyMetricPresentation.feedInPrice(
        dollarsPerKilowattHour: nil,
        mode: .full,
        locale: locale
      ).title,
      "Solar Payback Has Gone Walkabout"
    )
  }

  func testDailyMoneyPresentationUsesAustralianCurrency() {
    let cost = HomeEnergyMetricPresentation.costToday(
      dollars: 4.829,
      mode: .standard,
      locale: locale
    )
    let earnings = HomeEnergyMetricPresentation.feedInEarningsToday(
      dollars: 0.9086,
      mode: .standard,
      locale: locale
    )

    XCTAssertEqual(cost.title, "Cost today")
    XCTAssertEqual(cost.value, "$4.83")
    XCTAssertEqual(earnings.title, "Feed-in earnings")
    XCTAssertEqual(earnings.value, "$0.91")
  }

  func testFullBruceDailyMoneyPresentationGoesTheFullBruce() {
    let cost = HomeEnergyMetricPresentation.costToday(
      dollars: 4.83,
      mode: .full,
      locale: locale
    )
    let earnings = HomeEnergyMetricPresentation.feedInEarningsToday(
      dollars: 0.91,
      mode: .full,
      locale: locale
    )

    XCTAssertEqual(cost.title, "Today’s Wallet Barbecue")
    XCTAssertEqual(earnings.title, "Sunshine Cash Haul")
  }

  func testPendingDailyMoneyUsesModeSpecificUpdatingCopy() {
    let standard = HomeEnergyMetricPresentation.costToday(
      dollars: nil,
      status: .refreshing,
      mode: .standard,
      locale: locale
    )
    let fullBruce = HomeEnergyMetricPresentation.feedInEarningsToday(
      dollars: nil,
      status: .refreshing,
      mode: .full,
      locale: locale
    )

    XCTAssertEqual(standard.value, "Updating")
    XCTAssertTrue(standard.isUpdating)
    XCTAssertEqual(fullBruce.value, "Getting the latest")
    XCTAssertTrue(fullBruce.isUpdating)

    let lastKnown = HomeEnergyMetricPresentation.costToday(
      dollars: 4.83,
      status: .refreshing,
      mode: .full,
      locale: locale
    )
    XCTAssertEqual(
      lastKnown.statusText,
      "Last word Bruce got · Getting the latest"
    )
  }

  func testFailedDailyMoneyUsesBoldFullBruceCopy() {
    let standard = HomeEnergyMetricPresentation.costToday(
      dollars: nil,
      status: .failed,
      mode: .standard,
      locale: locale
    )
    let fullBruce = HomeEnergyMetricPresentation.feedInEarningsToday(
      dollars: nil,
      status: .failed,
      mode: .full,
      locale: locale
    )

    XCTAssertEqual(standard.value, "Update failed")
    XCTAssertTrue(standard.updateFailed)
    XCTAssertEqual(fullBruce.value, "Wallet radar carked it")
    XCTAssertTrue(fullBruce.updateFailed)

    let lastKnown = HomeEnergyMetricPresentation.costToday(
      dollars: 4.83,
      status: .failed,
      mode: .full,
      locale: locale
    )
    XCTAssertEqual(
      lastKnown.statusText,
      "Last haul · Wallet radar carked it"
    )
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

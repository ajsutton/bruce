import XCTest

@testable import Bruce

final class HomeEnergyChartSelectionTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_000_000)

  func testFlowReadoutInterpolatesTheLineAtTheCursor() {
    let history = HomeEnergyFlowHistory(
      interval: DateInterval(start: start, duration: 30),
      readings: [
        .init(series: .grid, timestamp: start, kilowatts: -2),
        .init(series: .homeUsage, timestamp: start, kilowatts: 8),
        .init(series: .grid, timestamp: start.addingTimeInterval(20), kilowatts: 4),
      ]
    )
    XCTAssertEqual(
      HomeEnergyChartSelection.flowValue(
        in: history, series: .grid, at: start.addingTimeInterval(10)), 1)
    XCTAssertEqual(
      HomeEnergyChartSelection.flowValue(in: history, series: .grid, at: history.interval.end), 4)
    XCTAssertNil(HomeEnergyChartSelection.flowValue(in: history, series: .battery, at: start))
  }

  func testFlowReadoutPreservesUnavailableIntervalsAndRecovery() {
    let history = HomeEnergyFlowHistory(
      interval: DateInterval(start: start, duration: 40),
      readings: [
        .init(series: .grid, timestamp: start.addingTimeInterval(5), kilowatts: -2),
        .init(series: .grid, timestamp: start.addingTimeInterval(10), kilowatts: nil),
        .init(series: .grid, timestamp: start.addingTimeInterval(20), kilowatts: 4),
      ]
    )
    XCTAssertNil(HomeEnergyChartSelection.flowValue(in: history, series: .grid, at: start))
    XCTAssertEqual(
      HomeEnergyChartSelection.flowValue(
        in: history, series: .grid, at: start.addingTimeInterval(9)), -2)
    XCTAssertNil(
      HomeEnergyChartSelection.flowValue(
        in: history, series: .grid, at: start.addingTimeInterval(10)))
    XCTAssertNil(
      HomeEnergyChartSelection.flowValue(
        in: history, series: .grid, at: start.addingTimeInterval(15)))
    XCTAssertEqual(
      HomeEnergyChartSelection.flowValue(
        in: history, series: .grid, at: start.addingTimeInterval(20)), 4)
    XCTAssertNil(
      HomeEnergyChartSelection.flowValue(
        in: history, series: .grid, at: start.addingTimeInterval(41)))
  }

  func testPriceReadoutUsesTheActiveTariffWithoutInterpolating() {
    let history = HomeEnergyPriceHistory(
      interval: DateInterval(start: start, duration: 40),
      readings: [
        .init(tariff: .general, timestamp: start, dollarsPerKilowattHour: -0.1),
        .init(tariff: .feedIn, timestamp: start, dollarsPerKilowattHour: 0.05),
        .init(
          tariff: .general, timestamp: start.addingTimeInterval(20), dollarsPerKilowattHour: 0.3),
      ]
    )
    XCTAssertEqual(
      HomeEnergyChartSelection.priceValue(
        in: history, tariff: .general, at: start.addingTimeInterval(19)), -10)
    XCTAssertEqual(
      HomeEnergyChartSelection.priceValue(
        in: history, tariff: .general, at: start.addingTimeInterval(20)), 30)
    XCTAssertEqual(
      HomeEnergyChartSelection.priceValue(in: history, tariff: .feedIn, at: history.interval.end), 5
    )
  }

  func testPriceReadoutDoesNotCarryValuesAcrossAnOutage() {
    let history = HomeEnergyPriceHistory(
      interval: DateInterval(start: start, duration: 40),
      readings: [
        .init(
          tariff: .general, timestamp: start.addingTimeInterval(5), dollarsPerKilowattHour: 0.2),
        .init(
          tariff: .general, timestamp: start.addingTimeInterval(10), dollarsPerKilowattHour: nil),
        .init(
          tariff: .general, timestamp: start.addingTimeInterval(20), dollarsPerKilowattHour: 0.3),
      ]
    )
    XCTAssertNil(HomeEnergyChartSelection.priceValue(in: history, tariff: .general, at: start))
    XCTAssertNil(
      HomeEnergyChartSelection.priceValue(
        in: history, tariff: .general, at: start.addingTimeInterval(10)))
    XCTAssertNil(
      HomeEnergyChartSelection.priceValue(
        in: history, tariff: .general, at: start.addingTimeInterval(15)))
    XCTAssertEqual(
      HomeEnergyChartSelection.priceValue(
        in: history, tariff: .general, at: start.addingTimeInterval(20)), 30)
    XCTAssertNil(
      HomeEnergyChartSelection.priceValue(
        in: history, tariff: .general, at: start.addingTimeInterval(41)))
  }

  func testBatteryReadoutUsesTheActiveChargeAndPreservesGaps() {
    let history = HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, duration: 40),
      readings: [
        .init(timestamp: start.addingTimeInterval(5), stateOfCharge: 30),
        .init(timestamp: start.addingTimeInterval(10), stateOfCharge: nil),
        .init(timestamp: start.addingTimeInterval(20), stateOfCharge: 40),
      ]
    )
    XCTAssertNil(HomeEnergyChartSelection.batteryValue(in: history, at: start))
    XCTAssertEqual(
      HomeEnergyChartSelection.batteryValue(in: history, at: start.addingTimeInterval(9)), 30)
    XCTAssertNil(
      HomeEnergyChartSelection.batteryValue(in: history, at: start.addingTimeInterval(10)))
    XCTAssertNil(
      HomeEnergyChartSelection.batteryValue(in: history, at: start.addingTimeInterval(15)))
    XCTAssertEqual(
      HomeEnergyChartSelection.batteryValue(in: history, at: start.addingTimeInterval(20)), 40)
    XCTAssertEqual(HomeEnergyChartSelection.batteryValue(in: history, at: history.interval.end), 40)
    XCTAssertNil(
      HomeEnergyChartSelection.batteryValue(in: history, at: start.addingTimeInterval(41)))
  }
}

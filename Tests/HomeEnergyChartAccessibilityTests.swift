import XCTest

@testable import Bruce

@MainActor
final class HomeEnergyChartAccessibilityTests: XCTestCase {
  func testFlowDescriptorPreservesSeriesGapsAndSymmetricScale() {
    let start = Date(timeIntervalSince1970: 500_000)
    let outage = start.addingTimeInterval(10)
    let recovery = start.addingTimeInterval(20)
    let end = start.addingTimeInterval(30)
    let history = HomeEnergyFlowHistory(
      interval: DateInterval(start: start, end: end),
      readings: [
        .init(series: .pvGeneration, timestamp: start, kilowatts: 8),
        .init(series: .homeUsage, timestamp: start, kilowatts: 2),
        .init(series: .grid, timestamp: start, kilowatts: -2),
        .init(series: .battery, timestamp: start, kilowatts: -4),
        .init(series: .grid, timestamp: outage, kilowatts: nil),
        .init(series: .grid, timestamp: recovery, kilowatts: 1),
      ]
    )
    let store = HomeEnergyFlowHistoryStore(
      loader: EmptyHomeEnergyHistoryLoader(),
      flowHistory: history
    )
    let chart = HomeAssistantHomeEnergyFlowChart(
      store: store,
      mode: .standard
    )

    XCTAssertEqual(chart.flowYDomain, -9...9)
    XCTAssertEqual(chart.flowAccessibilityDescriptor.series.count, 5)
    XCTAssertEqual(
      chart.flowAccessibilityDescriptor.series.map {
        $0.points.map(\.timestamp)
      },
      [
        [start, end],
        [start, end],
        [start, outage],
        [recovery, end],
        [start, end],
      ]
    )
  }

  func testBatteryDescriptorPreservesGapsAndExtendedEndpoints() {
    let start = Date(timeIntervalSince1970: 600_000)
    let outage = start.addingTimeInterval(10)
    let recovery = start.addingTimeInterval(20)
    let end = start.addingTimeInterval(30)
    let history = HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, end: end),
      readings: [
        .init(timestamp: start, stateOfCharge: 30),
        .init(timestamp: outage, stateOfCharge: nil),
        .init(timestamp: recovery, stateOfCharge: 40),
      ]
    )
    let store = HomeEnergyBatteryHistoryStore(
      loader: EmptyHomeEnergyHistoryLoader(),
      batteryHistory: history
    )
    let chart = HomeAssistantHomeEnergyBatteryChart(
      store: store,
      mode: .standard
    )

    XCTAssertEqual(chart.batteryAccessibilityDescriptor.series.count, 2)
    XCTAssertEqual(
      chart.batteryAccessibilityDescriptor.series.map {
        $0.points.map(\.timestamp)
      },
      [
        [start, outage],
        [recovery, end],
      ]
    )
  }

  func testPriceDescriptorPreservesTariffGapsAndExtendedEndpoints() {
    let start = Date(timeIntervalSince1970: 700_000)
    let outage = start.addingTimeInterval(10)
    let recovery = start.addingTimeInterval(20)
    let end = start.addingTimeInterval(30)
    let history = HomeEnergyPriceHistory(
      interval: DateInterval(start: start, end: end),
      readings: [
        .init(
          tariff: .general,
          timestamp: start,
          dollarsPerKilowattHour: 0.2
        ),
        .init(
          tariff: .feedIn,
          timestamp: start,
          dollarsPerKilowattHour: 0.05
        ),
        .init(
          tariff: .general,
          timestamp: outage,
          dollarsPerKilowattHour: nil
        ),
        .init(
          tariff: .general,
          timestamp: recovery,
          dollarsPerKilowattHour: 0.3
        ),
      ]
    )
    let store = HomeEnergyPriceHistoryStore(
      loader: EmptyHomeEnergyHistoryLoader(),
      priceHistory: history
    )
    let chart = HomeAssistantHomeEnergyPriceChart(
      store: store,
      mode: .standard
    )

    let series = chart.priceAccessibilityDescriptor.series
    XCTAssertEqual(series.count, 3)
    XCTAssertEqual(
      series.map { $0.points.map(\.timestamp) },
      [
        [start, outage],
        [recovery, end],
        [start, end],
      ]
    )
  }
}

private struct EmptyHomeEnergyHistoryLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }
}

import Foundation

struct DemoEnergy: HomeAssistantHomeEnergyLoading {
  let capturedAt: Date

  init(capturedAt: Date = .now) {
    self.capturedAt = capturedAt
  }

  var providesContinuousEnergyUpdates: Bool { true }

  var snapshot: HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.4, batteryStateOfCharge: 76, batteryPowerKilowatts: -2.6,
      homeConsumptionKilowatts: 3.1, gridPowerKilowatts: -2.7,
      generalPriceDollarsPerKilowattHour: 0.34, feedInPriceDollarsPerKilowattHour: 0.12,
      importCostLast24HoursDollars: 2.4, feedInEarningsLast24HoursDollars: 3.7,
      importCostLast24HoursCapturedAt: capturedAt, feedInEarningsLast24HoursCapturedAt: capturedAt
    )
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot { snapshot }

  func homeEnergyUpdates() -> HomeAssistantHomeEnergyUpdateStream {
    HomeAssistantHomeEnergyUpdateStream { $0.yield(.live(snapshot)) }
  }

  func loadHomeEnergyFlowHistory() async throws -> HomeEnergyFlowHistory {
    HomeEnergyFlowHistory(
      interval: interval,
      readings: (0...48).flatMap { index -> [HomeEnergyFlowHistory.Reading] in
        let solar = max(0, sin(Double(index) / 48 * .pi * 2 - .pi / 2)) * 8.4
        let home = 2 + Double(index % 5) * 0.3
        return [
          .init(series: .pvGeneration, timestamp: timestamp(index), kilowatts: solar),
          .init(series: .homeUsage, timestamp: timestamp(index), kilowatts: home),
          .init(series: .grid, timestamp: timestamp(index), kilowatts: home - solar),
          .init(series: .battery, timestamp: timestamp(index), kilowatts: solar > home ? -1 : 1),
        ]
      }
    )
  }

  func loadHomeEnergyBatteryHistory() async throws -> HomeEnergyBatteryHistory {
    HomeEnergyBatteryHistory(
      interval: interval,
      readings: (0...48).map {
        .init(timestamp: timestamp($0), stateOfCharge: 65 + sin(Double($0) / 10) * 20)
      }
    )
  }

  func loadHomeEnergyPriceHistory() async throws -> HomeEnergyPriceHistory {
    HomeEnergyPriceHistory(
      interval: interval,
      readings: (0...48).flatMap { index -> [HomeEnergyPriceHistory.Reading] in
        [
          .init(
            tariff: .general, timestamp: timestamp(index),
            dollarsPerKilowattHour: (32...40).contains(index) ? 0.44 : 0.28),
          .init(tariff: .feedIn, timestamp: timestamp(index), dollarsPerKilowattHour: 0.12),
        ]
      }
    )
  }

  private var interval: DateInterval {
    DateInterval(start: capturedAt.addingTimeInterval(-86400), end: capturedAt)
  }

  private func timestamp(_ index: Int) -> Date {
    capturedAt.addingTimeInterval(Double(index - 48) * 1800)
  }
}

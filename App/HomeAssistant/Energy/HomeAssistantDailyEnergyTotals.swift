import Foundation

struct HomeAssistantDailyEnergyTotals: Equatable, Sendable {
  let importCostDollars: Double?
  let feedInEarningsDollars: Double?
  let interval: DateInterval
  let importCounter: HomeAssistantEnergyCounterReference?
  let feedInCounter: HomeAssistantEnergyCounterReference?

  init(
    importCostDollars: Double?,
    feedInEarningsDollars: Double?,
    interval: DateInterval,
    importCounter: HomeAssistantEnergyCounterReference? = nil,
    feedInCounter: HomeAssistantEnergyCounterReference? = nil
  ) {
    self.importCostDollars = importCostDollars
    self.feedInEarningsDollars = feedInEarningsDollars
    self.interval = interval
    self.importCounter = importCounter
    self.feedInCounter = feedInCounter
  }
}

struct HomeAssistantEnergyCounterReference: Equatable, Sendable {
  let value: Double
  let lastReset: Date?
}

protocol HomeAssistantDailyEnergyTotalsLoading: Sendable {
  func loadDailyEnergyTotals() async throws -> HomeAssistantDailyEnergyTotals
}

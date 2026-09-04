import Foundation

struct HomeAssistantRollingEnergyTotals: Equatable, Sendable {
  let importCostDollars: Double?
  let feedInEarningsDollars: Double?
  let refreshAfter: Date
  let importCapturedAt: Date?
  let feedInCapturedAt: Date?

  init(
    importCostDollars: Double?,
    feedInEarningsDollars: Double?,
    refreshAfter: Date,
    importCapturedAt: Date? = nil,
    feedInCapturedAt: Date? = nil
  ) {
    self.importCostDollars = importCostDollars
    self.feedInEarningsDollars = feedInEarningsDollars
    self.refreshAfter = refreshAfter
    self.importCapturedAt = importCapturedAt
    self.feedInCapturedAt = feedInCapturedAt
  }
}

protocol HomeAssistantRollingEnergyTotalsLoading: Sendable {
  func loadRollingEnergyTotals() async throws -> HomeAssistantRollingEnergyTotals
}

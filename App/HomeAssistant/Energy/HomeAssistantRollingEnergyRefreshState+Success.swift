import Foundation

extension HomeAssistantRollingEnergyRefreshState {
  mutating func noteSuccess(
    _ totals: HomeAssistantRollingEnergyTotals,
    at timestamp: Date
  ) {
    let previous = authoritativeTotals
    let acceptsImport =
      totals.importCostDollars != nil
      && Self.isNotOlder(totals.importCapturedAt, than: previous?.importCapturedAt)
    let acceptsFeedIn =
      totals.feedInEarningsDollars != nil
      && Self.isNotOlder(totals.feedInCapturedAt, than: previous?.feedInCapturedAt)
    authoritativeTotals = Self.merging(
      totals,
      with: previous,
      acceptsImport: acceptsImport,
      acceptsFeedIn: acceptsFeedIn
    )
    needsAuthoritativeRefresh = RollingEnergyMetricFlags(
      importCost: !acceptsImport,
      feedInEarnings: !acceptsFeedIn
    )
    presentationValidity = RollingEnergyMetricFlags(
      importCost: authoritativeTotals?.importCostDollars != nil,
      feedInEarnings: authoritativeTotals?.feedInEarningsDollars != nil
    )
    retryAfter =
      needsAuthoritativeRefresh.hasAny
      ? timestamp.addingTimeInterval(Self.failureRetryInterval)
      : nil
  }

  private static func merging(
    _ loaded: HomeAssistantRollingEnergyTotals,
    with previous: HomeAssistantRollingEnergyTotals?,
    acceptsImport: Bool,
    acceptsFeedIn: Bool
  ) -> HomeAssistantRollingEnergyTotals {
    HomeAssistantRollingEnergyTotals(
      importCostDollars:
        acceptsImport ? loaded.importCostDollars : previous?.importCostDollars,
      feedInEarningsDollars:
        acceptsFeedIn
        ? loaded.feedInEarningsDollars : previous?.feedInEarningsDollars,
      refreshAfter: loaded.refreshAfter,
      importCapturedAt:
        acceptsImport ? loaded.importCapturedAt : previous?.importCapturedAt,
      feedInCapturedAt:
        acceptsFeedIn ? loaded.feedInCapturedAt : previous?.feedInCapturedAt
    )
  }

  private static func isNotOlder(_ current: Date?, than previous: Date?) -> Bool {
    guard let current, let previous else { return true }
    return current >= previous
  }
}

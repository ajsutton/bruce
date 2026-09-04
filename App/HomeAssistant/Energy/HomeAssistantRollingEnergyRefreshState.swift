import Foundation

struct HomeAssistantRollingEnergyRefreshState {
  // Recorder totals are unavailable from the pushed state stream. Keep the one
  // coalesced recorder transaction aligned with the widget's 15-minute cadence,
  // including failures, so retries never increase periodic network work.
  static let failureRetryInterval: TimeInterval = 15 * 60

  var authoritativeTotals: HomeAssistantRollingEnergyTotals?
  var retryAfter: Date?
  var needsAuthoritativeRefresh = RollingEnergyMetricFlags(
    importCost: true,
    feedInEarnings: true
  )
  var presentationValidity = RollingEnergyMetricFlags()
  var needsImportRefresh: Bool { needsAuthoritativeRefresh.importCost }
  var needsFeedInRefresh: Bool { needsAuthoritativeRefresh.feedInEarnings }
  var hasPresentableImportCost: Bool { presentationValidity.importCost }
  var hasPresentableFeedInEarnings: Bool { presentationValidity.feedInEarnings }

  mutating func noteControlTransition() {
    needsAuthoritativeRefresh = RollingEnergyMetricFlags(
      importCost: true,
      feedInEarnings: true
    )
    retryAfter = nil
  }

  mutating func shouldRefresh(at timestamp: Date) -> Bool {
    guard retryAfter.map({ timestamp >= $0 }) ?? true else { return false }
    guard let authoritativeTotals else { return true }
    if timestamp >= authoritativeTotals.refreshAfter,
      !needsAuthoritativeRefresh.hasAny
    {
      needsAuthoritativeRefresh = RollingEnergyMetricFlags(
        importCost: true,
        feedInEarnings: true
      )
      retryAfter = nil
    }
    return needsAuthoritativeRefresh.hasAny
  }

  mutating func noteFailure(at timestamp: Date) {
    retryAfter = timestamp.addingTimeInterval(Self.failureRetryInterval)
  }

  var totals: HomeAssistantRollingEnergyTotals? {
    authoritativeTotals
  }

  func nextRefreshDate(after timestamp: Date) -> Date? {
    let refreshAfter = authoritativeTotals?.refreshAfter
    if let retryAfter {
      guard let refreshAfter, timestamp < refreshAfter else { return retryAfter }
      return min(retryAfter, refreshAfter)
    }
    switch refreshAfter {
    case .some(let refreshAfter) where timestamp < refreshAfter:
      return refreshAfter
    default:
      return nil
    }
  }
}

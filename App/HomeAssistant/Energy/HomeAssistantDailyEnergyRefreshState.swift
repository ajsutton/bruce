import Foundation

struct HomeAssistantDailyEnergyRefreshState {
  static let failureRetryInterval: TimeInterval = 5 * 60

  var authoritativeTotals: HomeAssistantDailyEnergyTotals?
  var adjustmentCounters: DailyEnergyCounters?
  var lastObservedLiveCounters: DailyEnergyCounters?
  var retryAfter: Date?
  var needsAuthoritativeRefresh = DailyEnergyCounterFlags(
    importCost: true,
    feedInEarnings: true
  )
  var pendingResets = DailyEnergyCounterFlags()
  var resetCheckpoints = DailyEnergyResetCheckpoints()
  private var missingCounters = DailyEnergyCounterFlags()
  var presentationValidity = DailyEnergyCounterFlags()
  var detectedDiscontinuity = false
  var needsImportRefresh: Bool { needsAuthoritativeRefresh.importCost }
  var needsFeedInRefresh: Bool {
    needsAuthoritativeRefresh.feedInEarnings
  }
  var hasPresentableImportCost: Bool {
    presentationValidity.importCost
  }
  var hasPresentableFeedInEarnings: Bool {
    presentationValidity.feedInEarnings
  }
  var isRecoveringImportReset: Bool {
    pendingResets.importCost && resetCheckpoints.importCost != nil
  }
  var isRecoveringFeedInReset: Bool {
    pendingResets.feedInEarnings && resetCheckpoints.feedInEarnings != nil
  }

  mutating func noteControlTransition() {
    needsAuthoritativeRefresh = DailyEnergyCounterFlags(
      importCost: true,
      feedInEarnings: true
    )
    retryAfter = nil
    presentationValidity = DailyEnergyCounterFlags()
    detectedDiscontinuity = false
  }

  mutating func shouldRefresh(
    for snapshot: HomeAssistantHomeEnergySnapshot,
    at timestamp: Date
  ) -> Bool {
    let current = DailyEnergyCounters(snapshot: snapshot)
    let previousObservedCounters = lastObservedLiveCounters
    var resets =
      previousObservedCounters.map { current.resets(since: $0) }
      ?? DailyEnergyCounterFlags()
    resets.formUnion(
      DailyEnergyCounterFlags(
        importCost: missingCounters.importCost && current.importCost != nil,
        feedInEarnings:
          missingCounters.feedInEarnings
          && current.feedInEarnings != nil
      )
    )
    noteObservedCounters(current)
    detectedDiscontinuity = resets.importCost || resets.feedInEarnings
    captureResetCheckpoints(
      for: resets,
      previousCounters: previousObservedCounters,
      at: timestamp
    )
    if let authoritativeTotals,
      !Self.contains(timestamp, in: authoritativeTotals.interval)
    {
      pendingResets.formUnion(resets)
      needsAuthoritativeRefresh = DailyEnergyCounterFlags(
        importCost: true,
        feedInEarnings: true
      )
      presentationValidity = DailyEnergyCounterFlags()
      retryAfter = nil
      return true
    }
    if detectedDiscontinuity {
      pendingResets.formUnion(resets)
      needsAuthoritativeRefresh.formUnion(resets)
      retryAfter = nil
      presentationValidity.remove(resets)
      return true
    }
    guard retryAfter.map({ timestamp >= $0 }) ?? true else {
      return false
    }
    guard authoritativeTotals != nil else {
      return true
    }
    return needsAuthoritativeRefresh.hasAny
  }

  mutating func noteFailure(at timestamp: Date) {
    retryAfter = timestamp.addingTimeInterval(Self.failureRetryInterval)
  }

  func totals(
    adjustedFor snapshot: HomeAssistantHomeEnergySnapshot,
    at timestamp: Date
  ) -> HomeAssistantDailyEnergyTotals? {
    guard
      let authoritativeTotals,
      Self.contains(timestamp, in: authoritativeTotals.interval),
      let baseline = adjustmentCounters
    else {
      return nil
    }
    let current = DailyEnergyCounters(snapshot: snapshot)
    let liveResets =
      lastObservedLiveCounters.map { current.resets(since: $0) }
      ?? DailyEnergyCounterFlags()
    return HomeAssistantDailyEnergyTotals(
      importCostDollars: Self.adjusted(
        presentationValidity.importCost
          ? authoritativeTotals.importCostDollars
          : nil,
        baseline: (baseline.importCost, baseline.importLastReset),
        current: (current.importCost, current.importLastReset),
        liveResetDetected: liveResets.importCost
      ),
      feedInEarningsDollars: Self.adjusted(
        presentationValidity.feedInEarnings
          ? authoritativeTotals.feedInEarningsDollars
          : nil,
        baseline: (baseline.feedInEarnings, baseline.feedInLastReset),
        current: (current.feedInEarnings, current.feedInLastReset),
        liveResetDetected: liveResets.feedInEarnings
      ),
      interval: authoritativeTotals.interval
    )
  }

  func nextRefreshDate(after timestamp: Date) -> Date? {
    let intervalEnd = authoritativeTotals?.interval.end
    switch (retryAfter, intervalEnd) {
    case (.some(let retryAfter), .some(let intervalEnd)):
      return min(retryAfter, intervalEnd)
    case (.some(let retryAfter), .none):
      return retryAfter
    case (.none, .some(let intervalEnd)) where timestamp < intervalEnd:
      return intervalEnd
    default:
      return nil
    }
  }

  static func contains(
    _ timestamp: Date,
    in interval: DateInterval
  ) -> Bool {
    interval.start <= timestamp && timestamp < interval.end
  }

  static func adjusted(
    _ total: Double?,
    baseline: (value: Double?, lastReset: Date?),
    current: (value: Double?, lastReset: Date?),
    liveResetDetected: Bool
  ) -> Double? {
    guard !liveResetDetected else { return nil }
    if let baselineLastReset = baseline.lastReset,
      let currentLastReset = current.lastReset,
      baselineLastReset != currentLastReset
    {
      return nil
    }
    guard let total else { return nil }
    guard let baselineValue = baseline.value else { return total }
    guard let currentValue = current.value else { return nil }
    let delta = currentValue - baselineValue
    let adjusted = total + delta
    return adjusted.isFinite ? adjusted : nil
  }

  private mutating func noteObservedCounters(
    _ current: DailyEnergyCounters
  ) {
    missingCounters = DailyEnergyCounterFlags(
      importCost: current.importCost == nil,
      feedInEarnings: current.feedInEarnings == nil
    )
    lastObservedLiveCounters = current.preservingMissingValues(
      from: lastObservedLiveCounters
    )
  }
}

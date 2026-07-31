import Foundation

extension HomeAssistantDailyEnergyRefreshState {
  mutating func noteSuccess(
    _ totals: HomeAssistantDailyEnergyTotals,
    snapshot: HomeAssistantHomeEnergySnapshot
  ) {
    noteSuccess(totals, snapshot: snapshot, at: totals.interval.start)
  }

  mutating func noteSuccess(
    _ totals: HomeAssistantDailyEnergyTotals,
    snapshot: HomeAssistantHomeEnergySnapshot,
    at timestamp: Date
  ) {
    let previousTotals = authoritativeTotals
    let previousBaseline = adjustmentCounters
    let isSameInterval = previousTotals?.interval == totals.interval
    expireResetCheckpoints(outside: totals.interval)
    let resolution = resolveSuccess(
      totals,
      snapshot: snapshot,
      at: timestamp
    )
    authoritativeTotals = Self.merging(
      resolution.totals,
      with: isSameInterval ? previousTotals : nil
    )
    updateBaselines(
      resolution,
      previous: isSameInterval ? previousBaseline : nil
    )
    updateRefreshTracking(
      resolution,
      isSameInterval: isSameInterval,
      at: timestamp
    )
  }

  mutating func captureResetCheckpoints(
    for resets: DailyEnergyCounterFlags,
    previousCounters: DailyEnergyCounters?,
    at timestamp: Date
  ) {
    guard let authoritativeTotals, let baseline = adjustmentCounters,
      let previousCounters,
      Self.contains(timestamp, in: authoritativeTotals.interval)
    else {
      return
    }
    if resets.importCost, !pendingResets.importCost {
      resetCheckpoints.importCost = DailyEnergyResetCheckpoint(
        total: Self.adjusted(
          authoritativeTotals.importCostDollars,
          baseline: (baseline.importCost, baseline.importLastReset),
          current: (
            previousCounters.importCost,
            previousCounters.importLastReset
          ),
          liveResetDetected: false
        ),
        liveValue: previousCounters.importCost,
        liveLastReset: previousCounters.importLastReset,
        statistic: authoritativeTotals.importCounter,
        interval: authoritativeTotals.interval
      )
    }
    if resets.feedInEarnings, !pendingResets.feedInEarnings {
      resetCheckpoints.feedInEarnings = DailyEnergyResetCheckpoint(
        total: Self.adjusted(
          authoritativeTotals.feedInEarningsDollars,
          baseline: (
            baseline.feedInEarnings,
            baseline.feedInLastReset
          ),
          current: (
            previousCounters.feedInEarnings,
            previousCounters.feedInLastReset
          ),
          liveResetDetected: false
        ),
        liveValue: previousCounters.feedInEarnings,
        liveLastReset: previousCounters.feedInLastReset,
        statistic: authoritativeTotals.feedInCounter,
        interval: authoritativeTotals.interval
      )
    }
  }

  private func resolveSuccess(
    _ totals: HomeAssistantDailyEnergyTotals,
    snapshot: HomeAssistantHomeEnergySnapshot,
    at timestamp: Date
  ) -> DailyEnergySuccessResolution {
    let local = self.totals(adjustedFor: snapshot, at: timestamp)
    let live = DailyEnergyCounters(snapshot: snapshot)
    let acceptsImport = Self.accepts(
      totals.importCostDollars,
      counter: totals.importCounter,
      live: (live.importCost, live.importLastReset),
      pending: (
        pendingResets.importCost,
        resetCheckpoints.importCost
      )
    )
    let acceptsFeedIn = Self.accepts(
      totals.feedInEarningsDollars,
      counter: totals.feedInCounter,
      live: (live.feedInEarnings, live.feedInLastReset),
      pending: (
        pendingResets.feedInEarnings,
        resetCheckpoints.feedInEarnings
      )
    )
    return DailyEnergySuccessResolution(
      totals: HomeAssistantDailyEnergyTotals(
        importCostDollars:
          acceptsImport
          ? totals.importCostDollars
          : local?.importCostDollars ?? resetCheckpoints.importCost?.total,
        feedInEarningsDollars:
          acceptsFeedIn
          ? totals.feedInEarningsDollars
          : local?.feedInEarningsDollars
            ?? resetCheckpoints.feedInEarnings?.total,
        interval: totals.interval,
        importCounter:
          acceptsImport
          ? totals.importCounter
          : Self.liveReference(live.importCost, reset: live.importLastReset),
        feedInCounter:
          acceptsFeedIn
          ? totals.feedInCounter
          : Self.liveReference(
            live.feedInEarnings,
            reset: live.feedInLastReset
          )
      ),
      live: live,
      acceptsImport: acceptsImport,
      acceptsFeedIn: acceptsFeedIn,
      reportedImport: totals.importCostDollars != nil,
      reportedFeedIn: totals.feedInEarningsDollars != nil
    )
  }

  private mutating func updateBaselines(
    _ resolution: DailyEnergySuccessResolution,
    previous: DailyEnergyCounters?
  ) {
    let loaded = DailyEnergyCounters(
      live: resolution.live,
      authoritativeTotals: resolution.totals,
      resets: DailyEnergyCounterFlags(
        importCost: pendingResets.importCost && !resolution.acceptsImport,
        feedInEarnings:
          pendingResets.feedInEarnings && !resolution.acceptsFeedIn
      )
    )
    let baseline = DailyEnergyCounters(
      loaded: loaded,
      previous: previous,
      loadedImport: resolution.totals.importCostDollars != nil,
      loadedFeedIn: resolution.totals.feedInEarningsDollars != nil
    )
    adjustmentCounters = baseline
    lastObservedLiveCounters =
      resolution.live
      .preservingMissingValues(from: lastObservedLiveCounters)
      .advancingResetMarkers(to: baseline)
  }

  private mutating func updateRefreshTracking(
    _ resolution: DailyEnergySuccessResolution,
    isSameInterval: Bool,
    at timestamp: Date
  ) {
    let retainsImport =
      isSameInterval
      && !needsAuthoritativeRefresh.importCost
      && !resolution.reportedImport
    let retainsFeedIn =
      isSameInterval
      && !needsAuthoritativeRefresh.feedInEarnings
      && !resolution.reportedFeedIn
    needsAuthoritativeRefresh = DailyEnergyCounterFlags(
      importCost: !(resolution.acceptsImport || retainsImport),
      feedInEarnings: !(resolution.acceptsFeedIn || retainsFeedIn)
    )
    retryAfter =
      needsAuthoritativeRefresh.hasAny
      ? timestamp.addingTimeInterval(Self.failureRetryInterval)
      : nil
    updateImportTracking(
      accepted: resolution.acceptsImport,
      isSameInterval: isSameInterval
    )
    updateFeedInTracking(
      accepted: resolution.acceptsFeedIn,
      isSameInterval: isSameInterval
    )
    detectedDiscontinuity = false
  }

  private mutating func updateImportTracking(
    accepted: Bool,
    isSameInterval: Bool
  ) {
    if accepted {
      pendingResets.importCost = false
      resetCheckpoints.importCost = nil
      presentationValidity.importCost = true
    } else if resetCheckpoints.importCost?.total != nil {
      presentationValidity.importCost = true
    } else if !isSameInterval {
      presentationValidity.importCost = false
    }
  }

  private mutating func updateFeedInTracking(
    accepted: Bool,
    isSameInterval: Bool
  ) {
    if accepted {
      pendingResets.feedInEarnings = false
      resetCheckpoints.feedInEarnings = nil
      presentationValidity.feedInEarnings = true
    } else if resetCheckpoints.feedInEarnings?.total != nil {
      presentationValidity.feedInEarnings = true
    } else if !isSameInterval {
      presentationValidity.feedInEarnings = false
    }
  }

  private mutating func expireResetCheckpoints(
    outside interval: DateInterval
  ) {
    if resetCheckpoints.importCost?.interval != interval {
      resetCheckpoints.importCost = nil
      pendingResets.importCost = false
    }
    if resetCheckpoints.feedInEarnings?.interval != interval {
      resetCheckpoints.feedInEarnings = nil
      pendingResets.feedInEarnings = false
    }
  }

  private static func merging(
    _ loaded: HomeAssistantDailyEnergyTotals,
    with previous: HomeAssistantDailyEnergyTotals?
  ) -> HomeAssistantDailyEnergyTotals {
    HomeAssistantDailyEnergyTotals(
      importCostDollars:
        loaded.importCostDollars ?? previous?.importCostDollars,
      feedInEarningsDollars:
        loaded.feedInEarningsDollars ?? previous?.feedInEarningsDollars,
      interval: loaded.interval,
      importCounter:
        loaded.importCostDollars == nil
        ? previous?.importCounter
        : loaded.importCounter,
      feedInCounter:
        loaded.feedInEarningsDollars == nil
        ? previous?.feedInCounter
        : loaded.feedInCounter
    )
  }

  private static func accepts(
    _ total: Double?,
    counter: HomeAssistantEnergyCounterReference?,
    live: (value: Double?, lastReset: Date?),
    pending: (reset: Bool, checkpoint: DailyEnergyResetCheckpoint?)
  ) -> Bool {
    guard total != nil else { return false }
    if let counterReset = counter?.lastReset, let liveReset = live.lastReset,
      counterReset < liveReset
    {
      return false
    }
    guard pending.reset, let checkpoint = pending.checkpoint else {
      return true
    }
    guard let counter else { return false }
    if checkpoint.liveLastReset != live.lastReset {
      return counter.lastReset == live.lastReset
    }
    guard let liveValue = live.value, let previousValue = checkpoint.liveValue
    else {
      return false
    }
    return abs(counter.value - liveValue)
      < abs(counter.value - previousValue)
  }

  private static func liveReference(
    _ value: Double?,
    reset: Date?
  ) -> HomeAssistantEnergyCounterReference? {
    value.map {
      HomeAssistantEnergyCounterReference(value: $0, lastReset: reset)
    }
  }
}

struct DailyEnergyResetCheckpoint {
  let total: Double?
  let liveValue: Double?
  let liveLastReset: Date?
  let statistic: HomeAssistantEnergyCounterReference?
  let interval: DateInterval
}

struct DailyEnergyResetCheckpoints {
  var importCost: DailyEnergyResetCheckpoint?
  var feedInEarnings: DailyEnergyResetCheckpoint?
}

private struct DailyEnergySuccessResolution {
  let totals: HomeAssistantDailyEnergyTotals
  let live: DailyEnergyCounters
  let acceptsImport: Bool
  let acceptsFeedIn: Bool
  let reportedImport: Bool
  let reportedFeedIn: Bool
}

import Foundation

struct DailyEnergyCounterFlags {
  var importCost = false
  var feedInEarnings = false

  mutating func formUnion(_ other: Self) {
    importCost = importCost || other.importCost
    feedInEarnings = feedInEarnings || other.feedInEarnings
  }

  mutating func remove(_ other: Self) {
    if other.importCost {
      importCost = false
    }
    if other.feedInEarnings {
      feedInEarnings = false
    }
  }

  var hasAny: Bool {
    importCost || feedInEarnings
  }
}

struct DailyEnergyCounters {
  let importCost: Double?
  let feedInEarnings: Double?
  let importLastReset: Date?
  let feedInLastReset: Date?

  init(snapshot: HomeAssistantHomeEnergySnapshot) {
    importCost = snapshot.importCostCounterDollars
    feedInEarnings = snapshot.feedInEarningsCounterDollars
    importLastReset = snapshot.importCostCounterLastReset
    feedInLastReset = snapshot.feedInEarningsCounterLastReset
  }

  init(
    importCost: Double?,
    feedInEarnings: Double?,
    importLastReset: Date?,
    feedInLastReset: Date?
  ) {
    self.importCost = importCost
    self.feedInEarnings = feedInEarnings
    self.importLastReset = importLastReset
    self.feedInLastReset = feedInLastReset
  }

  init(
    live: Self,
    authoritativeTotals: HomeAssistantDailyEnergyTotals,
    resets: DailyEnergyCounterFlags
  ) {
    let importBaseline = Self.baseline(
      statistic: authoritativeTotals.importCounter,
      liveValue: live.importCost,
      liveLastReset: live.importLastReset,
      resetDetected: resets.importCost
    )
    let feedInBaseline = Self.baseline(
      statistic: authoritativeTotals.feedInCounter,
      liveValue: live.feedInEarnings,
      liveLastReset: live.feedInLastReset,
      resetDetected: resets.feedInEarnings
    )
    importCost = importBaseline.value
    feedInEarnings = feedInBaseline.value
    importLastReset = importBaseline.lastReset
    feedInLastReset = feedInBaseline.lastReset
  }

  init(
    loaded: Self,
    previous: Self?,
    loadedImport: Bool,
    loadedFeedIn: Bool
  ) {
    importCost =
      loadedImport ? loaded.importCost : previous?.importCost
    feedInEarnings =
      loadedFeedIn ? loaded.feedInEarnings : previous?.feedInEarnings
    importLastReset =
      loadedImport ? loaded.importLastReset : previous?.importLastReset
    feedInLastReset =
      loadedFeedIn ? loaded.feedInLastReset : previous?.feedInLastReset
  }

  func resets(since previous: Self) -> DailyEnergyCounterFlags {
    DailyEnergyCounterFlags(
      importCost: Self.didReset(
        from: previous.importCost,
        lastReset: previous.importLastReset,
        to: importCost,
        lastReset: importLastReset
      ),
      feedInEarnings: Self.didReset(
        from: previous.feedInEarnings,
        lastReset: previous.feedInLastReset,
        to: feedInEarnings,
        lastReset: feedInLastReset
      )
    )
  }

  func advancingResetMarkers(to baseline: Self) -> Self {
    let advancesImportReset =
      baseline.importLastReset.map { baselineReset in
        importLastReset.map { baselineReset > $0 } ?? false
      } ?? false
    let advancesFeedInReset =
      baseline.feedInLastReset.map { baselineReset in
        feedInLastReset.map { baselineReset > $0 } ?? false
      } ?? false
    return Self(
      importCost: advancesImportReset ? baseline.importCost : importCost,
      feedInEarnings:
        advancesFeedInReset ? baseline.feedInEarnings : feedInEarnings,
      importLastReset:
        advancesImportReset ? baseline.importLastReset : importLastReset,
      feedInLastReset:
        advancesFeedInReset ? baseline.feedInLastReset : feedInLastReset
    )
  }

  func preservingMissingValues(from previous: Self?) -> Self {
    Self(
      importCost: importCost ?? previous?.importCost,
      feedInEarnings: feedInEarnings ?? previous?.feedInEarnings,
      importLastReset:
        importCost == nil
        ? previous?.importLastReset
        : importLastReset ?? previous?.importLastReset,
      feedInLastReset:
        feedInEarnings == nil
        ? previous?.feedInLastReset
        : feedInLastReset ?? previous?.feedInLastReset
    )
  }

  private static func didReset(
    from previous: Double?,
    lastReset previousLastReset: Date?,
    to current: Double?,
    lastReset currentLastReset: Date?
  ) -> Bool {
    if let previousLastReset, let currentLastReset {
      if previousLastReset != currentLastReset {
        return true
      }
      guard let previous, let current else { return false }
      return current == 0 && previous != 0
    }
    guard let previous, let current else { return false }
    return current < previous
  }

  private static func baseline(
    statistic: HomeAssistantEnergyCounterReference?,
    liveValue: Double?,
    liveLastReset: Date?,
    resetDetected: Bool
  ) -> (value: Double?, lastReset: Date?) {
    guard let statistic else {
      return (liveValue, liveLastReset)
    }
    if let statisticReset = statistic.lastReset, let liveLastReset {
      if statisticReset < liveLastReset {
        return (liveValue, liveLastReset)
      }
      if statisticReset > liveLastReset {
        return (statistic.value, statisticReset)
      }
    }
    if resetDetected, liveValue.map({ statistic.value > $0 }) ?? true {
      return (liveValue, liveLastReset)
    }
    return (
      statistic.value,
      statistic.lastReset ?? liveLastReset
    )
  }
}

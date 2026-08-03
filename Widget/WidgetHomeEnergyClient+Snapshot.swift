import Foundation

extension WidgetHomeEnergyClient {
  static func snapshot(
    from states: [WidgetHomeAssistantState],
    totals: WidgetDailyEnergyTotals,
    capturedAt: Date
  ) -> HomeEnergyWidgetSnapshot {
    snapshot(
      from: WidgetHomeEnergyComponents(
        states: .success(states),
        dailyTotals: .success(totals)
      ),
      previous: nil,
      capturedAt: capturedAt,
      sourceIdentifier: "test"
    )
      ?? HomeEnergyWidgetSnapshot(
        capturedAt: capturedAt,
        pvPowerKilowatts: nil,
        batteryStateOfCharge: nil,
        homeConsumptionKilowatts: nil,
        gridPowerKilowatts: nil,
        generalPriceDollarsPerKilowattHour: nil,
        feedInPriceDollarsPerKilowattHour: nil,
        importCostTodayDollars: nil,
        feedInEarningsTodayDollars: nil
      )
  }

  static func snapshot(
    currentStates: [WidgetHomeAssistantState]?,
    currentTotals: WidgetDailyEnergyTotals?,
    previous: HomeEnergyWidgetSnapshot?,
    capturedAt: Date
  ) -> HomeEnergyWidgetSnapshot? {
    snapshot(
      from: WidgetHomeEnergyComponents(
        states: currentStates.map(WidgetHomeEnergyComponent.success)
          ?? .failure(.noReachableServer),
        dailyTotals: currentTotals.map(WidgetHomeEnergyComponent.success)
          ?? .failure(.noReachableServer)
      ),
      previous: previous,
      capturedAt: capturedAt,
      sourceIdentifier: previous?.sourceIdentifier ?? "test"
    )
  }

  static func snapshot(
    from components: WidgetHomeEnergyComponents,
    previous: HomeEnergyWidgetSnapshot?,
    capturedAt: Date,
    sourceIdentifier: String
  ) -> HomeEnergyWidgetSnapshot? {
    guard components.hasSuccess else { return nil }
    let (readings, readingsAreCurrent) = readings(
      from: components.states,
      previous: previous
    )
    let (loadedTotals, totalsAreCurrent) = totals(
      from: components.dailyTotals,
      previous: previous,
      capturedAt: capturedAt
    )
    let totals = reconciled(
      loadedTotals,
      states: components.states.value,
      previous: previous,
      capturedAt: capturedAt
    )
    return HomeEnergyWidgetSnapshot(
      sourceIdentifier: sourceIdentifier,
      capturedAt: capturedAt,
      pvPowerKilowatts: readings.pvPowerKilowatts,
      batteryStateOfCharge: readings.batteryStateOfCharge,
      homeConsumptionKilowatts: readings.homeConsumptionKilowatts,
      gridPowerKilowatts: readings.gridPowerKilowatts,
      generalPriceDollarsPerKilowattHour: readings.generalPriceDollarsPerKilowattHour,
      feedInPriceDollarsPerKilowattHour: readings.feedInPriceDollarsPerKilowattHour,
      importCostTodayDollars: totals.importCostDollars,
      feedInEarningsTodayDollars: totals.feedInEarningsDollars,
      readingsAreCurrent: readingsAreCurrent,
      importCostIsCurrent: totalsAreCurrent && totals.importIsCurrent,
      feedInEarningsIsCurrent: totalsAreCurrent && totals.feedInIsCurrent,
      readingsCapturedAt:
        readingsAreCurrent ? capturedAt : previous?.readingsCapturedAt,
      importCostCapturedAt:
        totalsAreCurrent && totals.importIsCurrent
        ? capturedAt : previous?.importCostCapturedAt,
      feedInEarningsCapturedAt:
        totalsAreCurrent && totals.feedInIsCurrent
        ? capturedAt : previous?.feedInEarningsCapturedAt,
      dailyEnergyInterval:
        totals.interval
        ?? (HomeEnergyWidgetSnapshot.interval(
          previous?.dailyEnergyInterval,
          contains: capturedAt
        )
          ? previous?.dailyEnergyInterval : nil)
    )
  }

  static func value(
    _ entityID: String,
    in states: [WidgetHomeAssistantState],
    minimum: Double? = nil,
    range: ClosedRange<Double>? = nil
  ) -> Double? {
    guard let state = states.first(where: { $0.entityID == entityID }),
      let value = Double(state.state), value.isFinite,
      minimum.map({ value >= $0 }) ?? true,
      range?.contains(value) ?? true
    else { return nil }
    return value
  }

  private static func readings(
    from component: WidgetHomeEnergyComponent<[WidgetHomeAssistantState]>,
    previous: HomeEnergyWidgetSnapshot?
  ) -> (WidgetHomeEnergyReadings, Bool) {
    switch component {
    case .success(let states): (WidgetHomeEnergyReadings(states: states), true)
    case .failure: (WidgetHomeEnergyReadings(snapshot: previous), false)
    }
  }

  private static func totals(
    from component: WidgetHomeEnergyComponent<WidgetDailyEnergyTotals>,
    previous: HomeEnergyWidgetSnapshot?,
    capturedAt: Date
  ) -> (WidgetDailyEnergyTotals, Bool) {
    switch component {
    case .success(let totals): return (totals, true)
    case .failure:
      let previousIsCurrentDay = HomeEnergyWidgetSnapshot.interval(
        previous?.dailyEnergyInterval,
        contains: capturedAt
      )
      let importCost = previousIsCurrentDay ? previous?.importCostTodayDollars : nil
      let feedInEarnings = previousIsCurrentDay ? previous?.feedInEarningsTodayDollars : nil
      return (
        WidgetDailyEnergyTotals(
          importCostDollars: importCost,
          feedInEarningsDollars: feedInEarnings,
          importIsCurrent: false,
          feedInIsCurrent: false
        ),
        false
      )
    }
  }

  private static func reconciled(
    _ totals: WidgetDailyEnergyTotals,
    states: [WidgetHomeAssistantState]?,
    previous: HomeEnergyWidgetSnapshot?,
    capturedAt: Date
  ) -> WidgetDailyEnergyTotals {
    guard
      totals.interval.map({ HomeEnergyWidgetSnapshot.interval($0, contains: capturedAt) }) ?? true
    else {
      return totals
    }
    let previousIsCurrentInterval =
      previous?.dailyEnergyInterval == totals.interval
      || HomeEnergyWidgetSnapshot.interval(previous?.dailyEnergyInterval, contains: capturedAt)
    let previousImportCost =
      previousIsCurrentInterval
      ? previous?.importCostTodayDollars : nil
    let previousFeedInEarnings =
      previousIsCurrentInterval
      ? previous?.feedInEarningsTodayDollars : nil
    guard let states else {
      return reconciledWithoutLiveCounters(
        totals,
        previousImportCost: previousImportCost,
        previousFeedInEarnings: previousFeedInEarnings
      )
    }
    let loadedImport =
      totals.importIsCurrent
      ? totals.importCostDollars : previousImportCost
    let loadedFeedIn =
      totals.feedInIsCurrent
      ? totals.feedInEarningsDollars : previousFeedInEarnings
    let importCost = adjusted(
      loadedImport,
      baseline: totals.importCounter,
      live: state(Self.importCostEntityID, in: states),
      previous: previousImportCost,
      isCurrent: totals.importIsCurrent
    )
    let feedInEarnings = adjusted(
      loadedFeedIn,
      baseline: totals.feedInCounter,
      live: state(Self.feedInEarningsEntityID, in: states),
      previous: previousFeedInEarnings,
      isCurrent: totals.feedInIsCurrent
    )
    return resolvedTotals(totals, importCost: importCost, feedInEarnings: feedInEarnings)
  }

  private static func reconciledWithoutLiveCounters(
    _ totals: WidgetDailyEnergyTotals,
    previousImportCost: Double?,
    previousFeedInEarnings: Double?
  ) -> WidgetDailyEnergyTotals {
    let importCost = currentOrPrevious(
      totals.importCostDollars,
      previous: previousImportCost,
      isCurrent: totals.importIsCurrent
    )
    let feedInEarnings = currentOrPrevious(
      totals.feedInEarningsDollars,
      previous: previousFeedInEarnings,
      isCurrent: totals.feedInIsCurrent
    )
    return resolvedTotals(totals, importCost: importCost, feedInEarnings: feedInEarnings)
  }

  private static func resolvedTotals(
    _ totals: WidgetDailyEnergyTotals,
    importCost: (value: Double?, isCurrent: Bool),
    feedInEarnings: (value: Double?, isCurrent: Bool)
  ) -> WidgetDailyEnergyTotals {
    WidgetDailyEnergyTotals(
      importCostDollars: importCost.value,
      feedInEarningsDollars: feedInEarnings.value,
      interval: totals.interval,
      importCounter: totals.importCounter,
      feedInCounter: totals.feedInCounter,
      importIsCurrent: importCost.isCurrent,
      feedInIsCurrent: feedInEarnings.isCurrent
    )
  }

  private static func adjusted(
    _ total: Double?,
    baseline: WidgetEnergyCounterReference?,
    live: (value: Double, lastReset: Date?)?,
    previous: Double?,
    isCurrent: Bool
  ) -> (value: Double?, isCurrent: Bool) {
    guard isCurrent else { return (previous, false) }
    guard let total else { return (previous, false) }
    guard let baseline, let live else {
      return (total, true)
    }
    if let baselineReset = baseline.lastReset, let liveReset = live.lastReset,
      baselineReset != liveReset
    {
      return (previous, false)
    }
    let adjusted = total + live.value - baseline.value
    guard adjusted.isFinite else { return (total, true) }
    return (adjusted, true)
  }

  private static func currentOrPrevious(
    _ total: Double?,
    previous: Double?,
    isCurrent: Bool
  ) -> (value: Double?, isCurrent: Bool) {
    guard isCurrent else { return (previous, false) }
    guard let total else { return (previous, false) }
    return (total, true)
  }

  private static func state(
    _ entityID: String,
    in states: [WidgetHomeAssistantState]
  ) -> (value: Double, lastReset: Date?)? {
    guard let state = states.first(where: { $0.entityID == entityID }),
      let value = Double(state.state), value.isFinite
    else { return nil }
    return (value, state.lastReset)
  }

  static let pvPowerEntityID = "sensor.sigen_plant_pv_power"
  static let batteryStateOfChargeEntityID =
    "sensor.sigen_plant_battery_state_of_charge"
  static let homeConsumptionEntityID = "sensor.sigen_plant_consumed_power"
  static let gridPowerEntityID = "sensor.sigen_plant_grid_active_power"
  static let generalPriceEntityID =
    "sensor.01krmdgkh60wyckeepvgtbbgv3_general_price"
  static let feedInPriceEntityID =
    "sensor.01krmdgkh60wyckeepvgtbbgv3_feed_in_price"
  static let importCostEntityID = "sensor.sigen_plant_total_imported_energy_cost"
  static let feedInEarningsEntityID =
    "sensor.sigen_plant_total_exported_energy_compensation"
}

extension WidgetHomeEnergyComponent {
  fileprivate var value: Value? {
    if case .success(let value) = self { return value }
    return nil
  }
}

enum WidgetHomeEnergyComponent<Value: Sendable>: Sendable {
  case success(Value)
  case failure(WidgetHomeEnergyError)

  var isSuccess: Bool {
    if case .success = self { return true }
    return false
  }

  var failure: WidgetHomeEnergyError? {
    if case .failure(let error) = self { return error }
    return nil
  }

  func preservingSuccess(from previous: Self) -> Self {
    if case .success = self { return self }
    if case .success = previous { return previous }
    return self
  }
}

struct WidgetHomeEnergyComponents: Sendable {
  let states: WidgetHomeEnergyComponent<[WidgetHomeAssistantState]>
  let dailyTotals: WidgetHomeEnergyComponent<WidgetDailyEnergyTotals>

  var hasSuccess: Bool { states.isSuccess || dailyTotals.isSuccess }
  var needsAuthenticationRefresh: Bool {
    states.failure == .unauthorized || dailyTotals.failure == .unauthorized
  }
  var failure: WidgetHomeEnergyError? { states.failure ?? dailyTotals.failure }

  func preservingSuccesses(from previous: Self) -> Self {
    Self(
      states: states.preservingSuccess(from: previous.states),
      dailyTotals: dailyTotals.preservingSuccess(from: previous.dailyTotals)
    )
  }
}

private struct WidgetHomeEnergyReadings {
  let pvPowerKilowatts: Double?
  let batteryStateOfCharge: Double?
  let homeConsumptionKilowatts: Double?
  let gridPowerKilowatts: Double?
  let generalPriceDollarsPerKilowattHour: Double?
  let feedInPriceDollarsPerKilowattHour: Double?

  init(states: [WidgetHomeAssistantState]) {
    pvPowerKilowatts = WidgetHomeEnergyClient.value(
      WidgetHomeEnergyClient.pvPowerEntityID,
      in: states,
      minimum: 0
    )
    batteryStateOfCharge = WidgetHomeEnergyClient.value(
      WidgetHomeEnergyClient.batteryStateOfChargeEntityID,
      in: states,
      range: 0...100
    )
    homeConsumptionKilowatts = WidgetHomeEnergyClient.value(
      WidgetHomeEnergyClient.homeConsumptionEntityID,
      in: states,
      minimum: 0
    )
    gridPowerKilowatts = WidgetHomeEnergyClient.value(
      WidgetHomeEnergyClient.gridPowerEntityID,
      in: states
    )
    generalPriceDollarsPerKilowattHour = WidgetHomeEnergyClient.value(
      WidgetHomeEnergyClient.generalPriceEntityID,
      in: states
    )
    feedInPriceDollarsPerKilowattHour = WidgetHomeEnergyClient.value(
      WidgetHomeEnergyClient.feedInPriceEntityID,
      in: states
    )
  }

  init(snapshot: HomeEnergyWidgetSnapshot?) {
    pvPowerKilowatts = snapshot?.pvPowerKilowatts
    batteryStateOfCharge = snapshot?.batteryStateOfCharge
    homeConsumptionKilowatts = snapshot?.homeConsumptionKilowatts
    gridPowerKilowatts = snapshot?.gridPowerKilowatts
    generalPriceDollarsPerKilowattHour = snapshot?.generalPriceDollarsPerKilowattHour
    feedInPriceDollarsPerKilowattHour = snapshot?.feedInPriceDollarsPerKilowattHour
  }
}

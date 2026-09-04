import Foundation

extension WidgetHomeEnergyClient {
  static func snapshot(
    from states: [WidgetHomeAssistantState],
    totals: WidgetRollingEnergyTotals,
    capturedAt: Date
  ) -> HomeEnergyWidgetSnapshot {
    snapshot(
      from: WidgetHomeEnergyComponents(
        states: .success(states),
        rollingTotals: .success(totals)
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
        importCostLast24HoursDollars: nil,
        feedInEarningsLast24HoursDollars: nil
      )
  }

  static func snapshot(
    currentStates: [WidgetHomeAssistantState]?,
    currentTotals: WidgetRollingEnergyTotals?,
    previous: HomeEnergyWidgetSnapshot?,
    capturedAt: Date
  ) -> HomeEnergyWidgetSnapshot? {
    snapshot(
      from: WidgetHomeEnergyComponents(
        states: currentStates.map(WidgetHomeEnergyComponent.success)
          ?? .failure(.noReachableServer),
        rollingTotals: currentTotals.map(WidgetHomeEnergyComponent.success)
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
      from: components.rollingTotals,
      previous: previous
    )
    let totals = reconciled(
      loadedTotals,
      previous: previous
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
      importCostLast24HoursDollars: totals.importCostDollars,
      feedInEarningsLast24HoursDollars: totals.feedInEarningsDollars,
      readingsAreCurrent: readingsAreCurrent,
      importCostIsCurrent: totalsAreCurrent && totals.importIsCurrent,
      feedInEarningsIsCurrent: totalsAreCurrent && totals.feedInIsCurrent,
      readingsCapturedAt:
        readingsAreCurrent ? capturedAt : previous?.readingsCapturedAt,
      importCostCapturedAt:
        totalsAreCurrent && totals.importIsCurrent
        ? totals.importCapturedAt ?? capturedAt : previous?.importCostCapturedAt,
      feedInEarningsCapturedAt:
        totalsAreCurrent && totals.feedInIsCurrent
        ? totals.feedInCapturedAt ?? capturedAt : previous?.feedInEarningsCapturedAt
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
    from component: WidgetHomeEnergyComponent<WidgetRollingEnergyTotals>,
    previous: HomeEnergyWidgetSnapshot?
  ) -> (WidgetRollingEnergyTotals, Bool) {
    switch component {
    case .success(let totals): return (totals, true)
    case .failure:
      return (
        WidgetRollingEnergyTotals(
          importCostDollars: previous?.importCostLast24HoursDollars,
          feedInEarningsDollars: previous?.feedInEarningsLast24HoursDollars,
          importIsCurrent: false,
          feedInIsCurrent: false
        ),
        false
      )
    }
  }

  private static func reconciled(
    _ totals: WidgetRollingEnergyTotals,
    previous: HomeEnergyWidgetSnapshot?
  ) -> WidgetRollingEnergyTotals {
    let previousImportCost = previous?.importCostLast24HoursDollars
    let previousFeedInEarnings = previous?.feedInEarningsLast24HoursDollars
    let importIsNewer = Self.isNewer(
      totals.importCapturedAt,
      than:
        previousImportCost == nil
        ? nil : previous?.importCostCapturedAt
    )
    let feedInIsNewer = Self.isNewer(
      totals.feedInCapturedAt,
      than:
        previousFeedInEarnings == nil
        ? nil : previous?.feedInEarningsCapturedAt
    )
    return reconciledTotals(
      totals,
      previousImportCost: previousImportCost,
      previousFeedInEarnings: previousFeedInEarnings,
      importIsCurrent: totals.importIsCurrent && importIsNewer,
      feedInIsCurrent: totals.feedInIsCurrent && feedInIsNewer
    )
  }

  private static func reconciledTotals(
    _ totals: WidgetRollingEnergyTotals,
    previousImportCost: Double?,
    previousFeedInEarnings: Double?,
    importIsCurrent: Bool? = nil,
    feedInIsCurrent: Bool? = nil
  ) -> WidgetRollingEnergyTotals {
    let importCost = currentOrPrevious(
      totals.importCostDollars,
      previous: previousImportCost,
      isCurrent: importIsCurrent ?? totals.importIsCurrent
    )
    let feedInEarnings = currentOrPrevious(
      totals.feedInEarningsDollars,
      previous: previousFeedInEarnings,
      isCurrent: feedInIsCurrent ?? totals.feedInIsCurrent
    )
    return resolvedTotals(totals, importCost: importCost, feedInEarnings: feedInEarnings)
  }

  private static func resolvedTotals(
    _ totals: WidgetRollingEnergyTotals,
    importCost: (value: Double?, isCurrent: Bool),
    feedInEarnings: (value: Double?, isCurrent: Bool)
  ) -> WidgetRollingEnergyTotals {
    WidgetRollingEnergyTotals(
      importCostDollars: importCost.value,
      feedInEarningsDollars: feedInEarnings.value,
      importCapturedAt: totals.importCapturedAt,
      feedInCapturedAt: totals.feedInCapturedAt,
      importIsCurrent: importCost.isCurrent,
      feedInIsCurrent: feedInEarnings.isCurrent
    )
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

  private static func isNewer(_ current: Date?, than previous: Date?) -> Bool {
    guard let current, let previous else { return true }
    return current >= previous
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
  let rollingTotals: WidgetHomeEnergyComponent<WidgetRollingEnergyTotals>

  var hasSuccess: Bool { states.isSuccess || rollingTotals.isSuccess }
  var needsAuthenticationRefresh: Bool {
    states.failure == .unauthorized || rollingTotals.failure == .unauthorized
  }
  var failure: WidgetHomeEnergyError? { states.failure ?? rollingTotals.failure }

  func preservingSuccesses(from previous: Self) -> Self {
    Self(
      states: states.preservingSuccess(from: previous.states),
      rollingTotals: rollingTotals.preservingSuccess(from: previous.rollingTotals)
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

import Foundation

extension HomeEnergyWidgetSnapshot {
  init(
    snapshot: HomeAssistantHomeEnergySnapshot,
    capturedAt: Date,
    sourceIdentifier: String = "test",
    previous: HomeEnergyWidgetSnapshot? = nil
  ) {
    let selections = Self.rollingSelections(
      snapshot: snapshot,
      previous: previous,
      capturedAt: capturedAt
    )
    self.init(
      sourceIdentifier: sourceIdentifier,
      capturedAt: capturedAt,
      pvPowerKilowatts: Self.quantized(snapshot.pvPowerKilowatts, scale: 10),
      batteryStateOfCharge: Self.quantized(snapshot.batteryStateOfCharge, scale: 1),
      homeConsumptionKilowatts: Self.quantized(snapshot.homeConsumptionKilowatts, scale: 10),
      gridPowerKilowatts: Self.quantized(snapshot.gridPowerKilowatts, scale: 10),
      generalPriceDollarsPerKilowattHour:
        Self.quantized(snapshot.generalPriceDollarsPerKilowattHour, scale: 1_000),
      feedInPriceDollarsPerKilowattHour:
        Self.quantized(snapshot.feedInPriceDollarsPerKilowattHour, scale: 1_000),
      importCostLast24HoursDollars: Self.quantized(selections.importCost.value, scale: 100),
      feedInEarningsLast24HoursDollars: Self.quantized(selections.feedIn.value, scale: 100),
      importCostIsCurrent: selections.importCost.isCurrent,
      feedInEarningsIsCurrent: selections.feedIn.isCurrent,
      importCostCapturedAt: selections.importCost.capture,
      feedInEarningsCapturedAt: selections.feedIn.capture
    )
  }

  private static func rollingSelections(
    snapshot: HomeAssistantHomeEnergySnapshot,
    previous: HomeEnergyWidgetSnapshot?,
    capturedAt: Date
  ) -> RollingWidgetSelections {
    RollingWidgetSelections(
      importCost: rollingSelection(
        current: RollingWidgetMetricCandidate(
          value: snapshot.importCostLast24HoursDollars,
          capture: snapshot.importCostLast24HoursCapturedAt ?? capturedAt,
          isCurrent: snapshot.importCostLast24HoursStatus == .current
        ),
        previous: RollingWidgetMetricCandidate(
          value: previous?.importCostLast24HoursDollars,
          capture: previous?.importCostCapturedAt ?? capturedAt,
          isCurrent: previous?.importCostIsCurrent == true
        )
      ),
      feedIn: rollingSelection(
        current: RollingWidgetMetricCandidate(
          value: snapshot.feedInEarningsLast24HoursDollars,
          capture: snapshot.feedInEarningsLast24HoursCapturedAt ?? capturedAt,
          isCurrent: snapshot.feedInEarningsLast24HoursStatus == .current
        ),
        previous: RollingWidgetMetricCandidate(
          value: previous?.feedInEarningsLast24HoursDollars,
          capture: previous?.feedInEarningsCapturedAt ?? capturedAt,
          isCurrent: previous?.feedInEarningsIsCurrent == true
        )
      )
    )
  }

  private static func rollingSelection(
    current: RollingWidgetMetricCandidate,
    previous: RollingWidgetMetricCandidate
  ) -> RollingWidgetMetricCandidate {
    if current.isCurrent,
      previous.value == nil || current.capture >= previous.capture
    {
      return current
    }
    guard previous.value != nil else {
      return RollingWidgetMetricCandidate(
        value: nil,
        capture: current.capture,
        isCurrent: false
      )
    }
    return RollingWidgetMetricCandidate(
      value: previous.value,
      capture: previous.capture,
      isCurrent: current.isCurrent && previous.isCurrent
    )
  }

  private static func quantized(_ value: Double?, scale: Double) -> Double? {
    value.map { ($0 * scale).rounded(.toNearestOrEven) / scale }
  }
}

private struct RollingWidgetMetricCandidate {
  let value: Double?
  let capture: Date
  let isCurrent: Bool
}

private struct RollingWidgetSelections {
  let importCost: RollingWidgetMetricCandidate
  let feedIn: RollingWidgetMetricCandidate
}

import Foundation

extension HomeEnergyWidgetSnapshot {
  init(
    snapshot: HomeAssistantHomeEnergySnapshot,
    capturedAt: Date,
    sourceIdentifier: String = "test",
    previous: HomeEnergyWidgetSnapshot? = nil
  ) {
    let previousIsCurrentDay = Self.interval(previous?.dailyEnergyInterval, contains: capturedAt)
    let canReuseImportCost = snapshot.importCostTodayStatus == .current || previousIsCurrentDay
    let canReuseFeedInEarnings =
      snapshot.feedInEarningsTodayStatus == .current || previousIsCurrentDay
    let importCost =
      snapshot.importCostTodayStatus == .current
      ? snapshot.importCostTodayDollars
      : snapshot.importCostTodayDollars ?? previous?.importCostTodayDollars
    let feedInEarnings =
      snapshot.feedInEarningsTodayStatus == .current
      ? snapshot.feedInEarningsTodayDollars
      : snapshot.feedInEarningsTodayDollars ?? previous?.feedInEarningsTodayDollars
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
      importCostTodayDollars: canReuseImportCost
        ? Self.quantized(importCost, scale: 100) : nil,
      feedInEarningsTodayDollars:
        canReuseFeedInEarnings
        ? Self.quantized(feedInEarnings, scale: 100) : nil,
      importCostIsCurrent: snapshot.importCostTodayStatus == .current,
      feedInEarningsIsCurrent: snapshot.feedInEarningsTodayStatus == .current,
      importCostCapturedAt:
        snapshot.importCostTodayStatus == .current
        ? capturedAt : canReuseImportCost ? previous?.importCostCapturedAt : capturedAt,
      feedInEarningsCapturedAt:
        snapshot.feedInEarningsTodayStatus == .current
        ? capturedAt : canReuseFeedInEarnings ? previous?.feedInEarningsCapturedAt : capturedAt,
      dailyEnergyInterval:
        snapshot.dailyEnergyInterval
        ?? (previousIsCurrentDay ? previous?.dailyEnergyInterval : nil)
    )
  }

  private static func quantized(_ value: Double?, scale: Double) -> Double? {
    value.map { ($0 * scale).rounded(.toNearestOrEven) / scale }
  }
}

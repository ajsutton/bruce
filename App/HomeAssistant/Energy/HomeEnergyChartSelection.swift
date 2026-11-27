import Foundation

/// Values at the cursor follow each chart's interpolation and preserve unavailable intervals.
enum HomeEnergyChartSelection {
  static func flowValue(
    in history: HomeEnergyFlowHistory, series: HomeEnergyFlowHistory.Series, at time: Date
  ) -> Double? {
    guard history.interval.contains(time),
      let previous = history.readings.last(where: { $0.series == series && $0.timestamp <= time }),
      let value = previous.kilowatts
    else { return nil }
    guard let next = history.readings.first(where: { $0.series == series && $0.timestamp > time }),
      let nextValue = next.kilowatts
    else { return value }
    let fraction =
      time.timeIntervalSince(previous.timestamp)
      / next.timestamp.timeIntervalSince(previous.timestamp)
    return value + (nextValue - value) * fraction
  }

  static func priceValue(
    in history: HomeEnergyPriceHistory, tariff: HomeEnergyPriceHistory.Tariff, at time: Date
  ) -> Double? {
    guard history.interval.contains(time) else { return nil }
    return history.readings.last(where: { $0.tariff == tariff && $0.timestamp <= time })?
      .centsPerKilowattHour
  }

  static func batteryValue(in history: HomeEnergyBatteryHistory, at time: Date) -> Double? {
    guard history.interval.contains(time) else { return nil }
    return history.readings.last(where: { $0.timestamp <= time })?.stateOfCharge
  }

  static func formatted(_ value: Double?, unit: String) -> String {
    guard let value else { return "—" }
    return value.formatted(.number.precision(.fractionLength(0...2))) + unit
  }
}

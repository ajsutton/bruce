import SwiftUI

struct HomeEnergyMetricPresentation {
  let title: String
  let value: String
  let icon: String
  let color: Color

  static func pv(
    kilowatts: Double?,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    Self(
      title: mode.isFullBruce && kilowatts != nil ? "Old mate sun’s cranking" : "PV generation",
      value: power(kilowatts, locale: locale),
      icon: "sun.max.fill",
      color: kilowatts == nil ? .secondary : .orange
    )
  }

  static func battery(
    stateOfCharge: Double?,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    Self(
      title: mode.isFullBruce && stateOfCharge != nil ? "Juice in the tank" : "Battery",
      value: percentage(stateOfCharge, locale: locale),
      icon: batteryIcon(stateOfCharge),
      color: batteryColor(stateOfCharge)
    )
  }

  static func consumption(
    kilowatts: Double?,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    Self(
      title: mode.isFullBruce && kilowatts != nil ? "House is on the chew" : "Usage",
      value: power(kilowatts, locale: locale),
      icon: "house.fill",
      color: kilowatts == nil ? .secondary : .blue
    )
  }

  static func grid(
    kilowatts: Double?,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    guard let kilowatts else {
      return Self(
        title: "Grid",
        value: "Unavailable",
        icon: "bolt.horizontal.circle",
        color: .secondary
      )
    }
    if kilowatts <= -0.1 {
      return Self(
        title: mode.isFullBruce ? "Flicking it back" : "Grid export",
        value: power(abs(kilowatts), locale: locale),
        icon: "arrow.up.right",
        color: .green
      )
    }
    if kilowatts >= 0.1 {
      return Self(
        title: mode.isFullBruce ? "Grid’s shouting a round" : "Grid import",
        value: power(kilowatts, locale: locale),
        icon: "arrow.down.left",
        color: .orange
      )
    }
    return Self(
      title: mode.isFullBruce ? "Grid’s on smoko" : "Grid idle",
      value: power(0, locale: locale),
      icon: "equal",
      color: .secondary
    )
  }

  private static func power(_ kilowatts: Double?, locale: Locale) -> String {
    guard let kilowatts else { return "Unavailable" }
    return
      "\(kilowatts.formatted(.number.locale(locale).precision(.fractionLength(1)))) kW"
  }

  private static func percentage(_ value: Double?, locale: Locale) -> String {
    guard let value else { return "Unavailable" }
    return value.formatted(
      .percent
        .locale(locale)
        .scale(1)
        .precision(.fractionLength(0))
    )
  }

  private static func batteryIcon(_ value: Double?) -> String {
    guard let value else { return "battery.0percent" }
    switch value {
    case 75...:
      return "battery.100percent"
    case 50...:
      return "battery.75percent"
    case 25...:
      return "battery.50percent"
    default:
      return "battery.25percent"
    }
  }

  private static func batteryColor(_ value: Double?) -> Color {
    guard let value else { return .secondary }
    if value < 20 {
      return .red
    }
    if value < 50 {
      return .orange
    }
    return .green
  }
}

import SwiftUI

struct HomeEnergyMetricPresentation {
  let title: String
  let value: String
  let icon: String
  let color: Color
  let accessibilityLabel: String

  static func pv(
    kilowatts: Double?,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    let copy = HomeEnergyCopy(mode: mode)
    return Self(
      title: kilowatts == nil ? copy.pvGenerationUnavailable : copy.pvGeneration,
      value: power(kilowatts, copy: copy, locale: locale),
      icon: "sun.max.fill",
      color: kilowatts == nil ? .secondary : .orange,
      accessibilityLabel:
        kilowatts == nil
        ? copy.pvGenerationUnavailableAccessibility
        : copy.pvGenerationAccessibility
    )
  }

  static func battery(
    stateOfCharge: Double?,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    let copy = HomeEnergyCopy(mode: mode)
    return Self(
      title: stateOfCharge == nil ? copy.batteryUnavailable : copy.battery,
      value: percentage(stateOfCharge, copy: copy, locale: locale),
      icon: batteryIcon(stateOfCharge),
      color: batteryColor(stateOfCharge),
      accessibilityLabel:
        stateOfCharge == nil
        ? copy.batteryUnavailableAccessibility
        : copy.batteryAccessibility
    )
  }

  static func consumption(
    kilowatts: Double?,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    let copy = HomeEnergyCopy(mode: mode)
    return Self(
      title: kilowatts == nil ? copy.usageUnavailable : copy.usage,
      value: power(kilowatts, copy: copy, locale: locale),
      icon: "house.fill",
      color: kilowatts == nil ? .secondary : .blue,
      accessibilityLabel:
        kilowatts == nil
        ? copy.usageUnavailableAccessibility
        : copy.usageAccessibility
    )
  }

  static func grid(
    kilowatts: Double?,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    let copy = HomeEnergyCopy(mode: mode)
    guard let kilowatts else {
      return Self(
        title: copy.grid,
        value: copy.unavailable,
        icon: "bolt.horizontal.circle",
        color: .secondary,
        accessibilityLabel: copy.gridAccessibility
      )
    }
    if kilowatts <= -0.1 {
      return Self(
        title: copy.gridExport,
        value: power(abs(kilowatts), copy: copy, locale: locale),
        icon: "arrow.up.right",
        color: .green,
        accessibilityLabel: copy.gridExportAccessibility
      )
    }
    if kilowatts >= 0.1 {
      return Self(
        title: copy.gridImport,
        value: power(kilowatts, copy: copy, locale: locale),
        icon: "arrow.down.left",
        color: .orange,
        accessibilityLabel: copy.gridImportAccessibility
      )
    }
    return Self(
      title: copy.gridIdle,
      value: power(0, copy: copy, locale: locale),
      icon: "equal",
      color: .secondary,
      accessibilityLabel: copy.gridIdleAccessibility
    )
  }

  private static func power(
    _ kilowatts: Double?,
    copy: HomeEnergyCopy,
    locale: Locale
  ) -> String {
    guard let kilowatts else { return copy.unavailable }
    return
      "\(kilowatts.formatted(.number.locale(locale).precision(.fractionLength(1)))) kW"
  }

  private static func percentage(
    _ value: Double?,
    copy: HomeEnergyCopy,
    locale: Locale
  ) -> String {
    guard let value else { return copy.unavailable }
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

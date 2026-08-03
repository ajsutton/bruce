import SwiftUI

struct EnergyWidgetMetric: Identifiable {
  let id: String
  let title: String
  let value: String
  let icon: String
  let color: Color
  let accessibilityLabel: String
  let isLastKnown: Bool
}

private struct EnergyWidgetMetricDescriptor {
  let title: String
  let accessibilityLabel: String
  let icon: String
  let color: Color
}

extension HomeEnergyWidgetSnapshot {
  func stableMetrics(copy: EnergyWidgetCopy, locale: Locale = .current) -> [EnergyWidgetMetric] {
    [
      EnergyWidgetMetric(
        id: "battery",
        title: copy.battery,
        value: percentage(batteryStateOfCharge, copy: copy, locale: locale),
        icon: batteryIcon,
        color: batteryColor,
        accessibilityLabel: copy.batteryAccessibility,
        isLastKnown: !readingsAreCurrent
      ),
      EnergyWidgetMetric(
        id: "cost",
        title: copy.costToday,
        value: currency(importCostTodayDollars, copy: copy, locale: locale),
        icon: "dollarsign.circle.fill",
        color: importCostTodayDollars == nil ? .secondary : .orange,
        accessibilityLabel: copy.costTodayAccessibility,
        isLastKnown: !importCostIsCurrent
      ),
      EnergyWidgetMetric(
        id: "earnings",
        title: copy.earningsToday,
        value: currency(feedInEarningsTodayDollars, copy: copy, locale: locale),
        icon: "banknote.fill",
        color: feedInEarningsTodayDollars == nil ? .secondary : .green,
        accessibilityLabel: copy.earningsTodayAccessibility,
        isLastKnown: !feedInEarningsIsCurrent
      ),
    ]
  }

  func changingMetrics(copy: EnergyWidgetCopy, locale: Locale = .current) -> [EnergyWidgetMetric] {
    [
      powerMetric(
        "solar",
        descriptor(
          copy.solar,
          copy.solarAccessibility,
          "sun.max.fill",
          .orange
        ),
        pvPowerKilowatts,
        copy,
        locale
      ),
      powerMetric(
        "usage",
        descriptor(
          copy.usage,
          copy.usageAccessibility,
          "house.fill",
          .blue
        ),
        homeConsumptionKilowatts,
        copy,
        locale
      ),
      gridMetric(copy: copy, locale: locale),
      priceMetric(
        "price",
        descriptor(
          copy.generalPrice,
          copy.generalPriceAccessibility,
          "bolt.fill",
          .orange
        ),
        generalPriceDollarsPerKilowattHour,
        copy,
        locale
      ),
      feedInMetric(copy: copy, locale: locale),
    ]
  }

  private func gridMetric(copy: EnergyWidgetCopy, locale: Locale) -> EnergyWidgetMetric {
    guard let gridPowerKilowatts else {
      return powerMetric(
        "grid",
        descriptor(
          copy.gridIdle,
          copy.gridIdleAccessibility,
          "bolt.horizontal.circle",
          .secondary
        ),
        nil,
        copy,
        locale
      )
    }
    if gridPowerKilowatts <= -0.1 {
      return powerMetric(
        "grid",
        descriptor(
          copy.gridExport,
          copy.gridExportAccessibility,
          "arrow.up.right",
          .green
        ),
        abs(gridPowerKilowatts),
        copy,
        locale
      )
    }
    if gridPowerKilowatts >= 0.1 {
      return powerMetric(
        "grid",
        descriptor(
          copy.gridImport,
          copy.gridImportAccessibility,
          "arrow.down.left",
          .orange
        ),
        gridPowerKilowatts,
        copy,
        locale
      )
    }
    return powerMetric(
      "grid",
      descriptor(copy.gridIdle, copy.gridIdleAccessibility, "equal", .secondary),
      0,
      copy,
      locale
    )
  }

  private func feedInMetric(copy: EnergyWidgetCopy, locale: Locale) -> EnergyWidgetMetric {
    if let feedInPriceDollarsPerKilowattHour, feedInPriceDollarsPerKilowattHour < 0 {
      return priceMetric(
        "feedIn",
        descriptor(
          copy.feedInCharge,
          copy.feedInChargeAccessibility,
          "exclamationmark.triangle.fill",
          .orange
        ),
        abs(feedInPriceDollarsPerKilowattHour),
        copy,
        locale
      )
    }
    return priceMetric(
      "feedIn",
      descriptor(
        copy.feedInPrice,
        copy.feedInPriceAccessibility,
        "arrow.up.right.circle.fill",
        .green
      ),
      feedInPriceDollarsPerKilowattHour,
      copy,
      locale
    )
  }

  private func powerMetric(
    _ id: String,
    _ descriptor: EnergyWidgetMetricDescriptor,
    _ value: Double?,
    _ copy: EnergyWidgetCopy,
    _ locale: Locale
  ) -> EnergyWidgetMetric {
    EnergyWidgetMetric(
      id: id,
      title: descriptor.title,
      value: value.map {
        "\($0.formatted(.number.locale(locale).precision(.fractionLength(1)))) kW"
      } ?? copy.unavailable,
      icon: descriptor.icon,
      color: value == nil ? .secondary : descriptor.color,
      accessibilityLabel: descriptor.accessibilityLabel,
      isLastKnown: !readingsAreCurrent
    )
  }

  private func priceMetric(
    _ id: String,
    _ descriptor: EnergyWidgetMetricDescriptor,
    _ value: Double?,
    _ copy: EnergyWidgetCopy,
    _ locale: Locale
  ) -> EnergyWidgetMetric {
    EnergyWidgetMetric(
      id: id,
      title: descriptor.title,
      value: value.map {
        let cents = ($0 * 100).formatted(
          .number.locale(locale).precision(.fractionLength(0...1))
        )
        return "\(cents)¢/kWh"
      } ?? copy.unavailable,
      icon: descriptor.icon,
      color: value == nil ? .secondary : descriptor.color,
      accessibilityLabel: descriptor.accessibilityLabel,
      isLastKnown: !readingsAreCurrent
    )
  }

  private func descriptor(
    _ title: String,
    _ accessibilityLabel: String,
    _ icon: String,
    _ color: Color
  ) -> EnergyWidgetMetricDescriptor {
    EnergyWidgetMetricDescriptor(
      title: title,
      accessibilityLabel: accessibilityLabel,
      icon: icon,
      color: color
    )
  }

  private func percentage(
    _ value: Double?,
    copy: EnergyWidgetCopy,
    locale: Locale
  ) -> String {
    value?.formatted(
      .percent.locale(locale).scale(1).precision(.fractionLength(0))
    ) ?? copy.unavailable
  }

  private func currency(
    _ value: Double?,
    copy: EnergyWidgetCopy,
    locale: Locale
  ) -> String {
    value?.formatted(
      .currency(code: "AUD").locale(locale).precision(.fractionLength(2))
    ) ?? copy.unavailable
  }

  private var batteryIcon: String {
    guard let batteryStateOfCharge else { return "battery.0percent" }
    return switch batteryStateOfCharge {
    case 75...: "battery.100percent"
    case 50...: "battery.75percent"
    case 25...: "battery.50percent"
    default: "battery.25percent"
    }
  }

  private var batteryColor: Color {
    guard let batteryStateOfCharge else { return .secondary }
    if batteryStateOfCharge < 20 { return .red }
    if batteryStateOfCharge < 50 { return .orange }
    return .green
  }
}

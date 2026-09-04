import SwiftUI

extension HomeEnergyMetricPresentation {
  static func costLast24Hours(
    dollars: Double?,
    status: HomeAssistantRollingEnergyMetricStatus = .current,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    let copy = HomeEnergyCopy(mode: mode)
    return Self(
      title: copy.costLast24Hours,
      value: rollingTotalValue(
        dollars,
        status: status,
        copy: copy,
        locale: locale
      ),
      icon: "dollarsign.circle.fill",
      color: dollars == nil ? .secondary : .orange,
      accessibilityLabel: copy.costLast24HoursAccessibility,
      statusText: rollingTotalStatus(dollars, status: status, copy: copy),
      isUpdating: status == .refreshing,
      updateFailed: status == .failed
    )
  }

  static func feedInEarningsLast24Hours(
    dollars: Double?,
    status: HomeAssistantRollingEnergyMetricStatus = .current,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    let copy = HomeEnergyCopy(mode: mode)
    return Self(
      title: copy.feedInEarningsLast24Hours,
      value: rollingTotalValue(
        dollars,
        status: status,
        copy: copy,
        locale: locale
      ),
      icon: "banknote.fill",
      color: dollars == nil ? .secondary : .green,
      accessibilityLabel: copy.feedInEarningsLast24HoursAccessibility,
      statusText: rollingTotalStatus(dollars, status: status, copy: copy),
      isUpdating: status == .refreshing,
      updateFailed: status == .failed
    )
  }

  private static func rollingTotalValue(
    _ dollars: Double?,
    status: HomeAssistantRollingEnergyMetricStatus,
    copy: HomeEnergyCopy,
    locale: Locale
  ) -> String {
    if status == .refreshing, dollars == nil {
      return copy.updating
    }
    if status == .failed, dollars == nil {
      return copy.rollingTotalsLoadFailed
    }
    guard let dollars else { return copy.unavailable }
    return dollars.formatted(
      .currency(code: "AUD")
        .locale(locale)
        .precision(.fractionLength(2))
    )
  }

  private static func rollingTotalStatus(
    _ dollars: Double?,
    status: HomeAssistantRollingEnergyMetricStatus,
    copy: HomeEnergyCopy
  ) -> String? {
    guard dollars != nil else { return nil }
    return switch status {
    case .current:
      nil
    case .refreshing:
      copy.updatingLastKnownStatus
    case .failed:
      copy.rollingTotalsUpdateFailedLastKnownStatus
    }
  }
}

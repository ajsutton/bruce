import SwiftUI

extension HomeEnergyMetricPresentation {
  static func costToday(
    dollars: Double?,
    status: HomeAssistantDailyEnergyMetricStatus = .current,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    let copy = HomeEnergyCopy(mode: mode)
    return Self(
      title: copy.costToday,
      value: dailyTotalValue(
        dollars,
        status: status,
        copy: copy,
        locale: locale
      ),
      icon: "dollarsign.circle.fill",
      color: dollars == nil ? .secondary : .orange,
      accessibilityLabel: copy.costTodayAccessibility,
      statusText: dailyTotalStatus(dollars, status: status, copy: copy),
      isUpdating: status == .refreshing,
      updateFailed: status == .failed
    )
  }

  static func feedInEarningsToday(
    dollars: Double?,
    status: HomeAssistantDailyEnergyMetricStatus = .current,
    mode: BruceMode,
    locale: Locale = .current
  ) -> Self {
    let copy = HomeEnergyCopy(mode: mode)
    return Self(
      title: copy.feedInEarningsToday,
      value: dailyTotalValue(
        dollars,
        status: status,
        copy: copy,
        locale: locale
      ),
      icon: "banknote.fill",
      color: dollars == nil ? .secondary : .green,
      accessibilityLabel: copy.feedInEarningsTodayAccessibility,
      statusText: dailyTotalStatus(dollars, status: status, copy: copy),
      isUpdating: status == .refreshing,
      updateFailed: status == .failed
    )
  }

  private static func dailyTotalValue(
    _ dollars: Double?,
    status: HomeAssistantDailyEnergyMetricStatus,
    copy: HomeEnergyCopy,
    locale: Locale
  ) -> String {
    if status == .refreshing, dollars == nil {
      return copy.updating
    }
    if status == .failed, dollars == nil {
      return copy.dailyTotalsLoadFailed
    }
    guard let dollars else { return copy.unavailable }
    return dollars.formatted(
      .currency(code: "AUD")
        .locale(locale)
        .precision(.fractionLength(2))
    )
  }

  private static func dailyTotalStatus(
    _ dollars: Double?,
    status: HomeAssistantDailyEnergyMetricStatus,
    copy: HomeEnergyCopy
  ) -> String? {
    guard dollars != nil else { return nil }
    return switch status {
    case .current:
      nil
    case .refreshing:
      copy.updatingLastKnownStatus
    case .failed:
      copy.dailyTotalsUpdateFailedLastKnownStatus
    }
  }
}

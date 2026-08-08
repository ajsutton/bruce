import Foundation

struct EVChargingDecisionPresentation {
  enum Intent {
    case allowed
    case held
    case unavailable

    var icon: String {
      switch self {
      case .allowed: "checkmark.circle.fill"
      case .held: "pause.circle"
      case .unavailable: "questionmark.circle"
      }
    }
  }

  let intent: Intent
  let safeChargingTime: String
  let safeChargingTimeAccessibility: String
  let batteryStateOfCharge: String
  let batteryIcon: String
  let explanation: String

  init(
    decision: HomeAssistantEVChargingDecision,
    chargingMode: HomeAssistantEVChargingMode,
    mode: BruceMode,
    date: Date = Date(),
    calendar: Calendar = .current,
    locale: Locale = .current
  ) {
    let copy = EVChargingCopy(mode: mode)
    intent =
      switch decision.isChargingDesired {
      case true: .allowed
      case false: .held
      case nil: .unavailable
      }
    safeChargingTime = Self.safeChargingTime(
      minutes: decision.overnightSafeChargingMinutes,
      unavailable: copy.unavailable,
      locale: locale
    )
    safeChargingTimeAccessibility = Self.safeChargingTimeAccessibility(
      minutes: decision.overnightSafeChargingMinutes,
      unavailable: copy.unavailable,
      locale: locale
    )
    batteryStateOfCharge = Self.batteryStateOfCharge(
      decision.batteryStateOfCharge,
      unavailable: copy.unavailable,
      locale: locale
    )
    batteryIcon = Self.batteryIcon(
      stateOfCharge: decision.batteryStateOfCharge
    )
    explanation =
      EVChargingExplanationResolver(
        decision: decision,
        chargingMode: chargingMode,
        date: date,
        calendar: calendar,
        copy: copy,
        locale: locale
      ).text
  }

  private static func safeChargingTime(
    minutes: Double?,
    unavailable: String,
    locale: Locale
  ) -> String {
    guard let minutes else { return unavailable }
    let totalMinutes = Int(minutes.rounded())
    let hours = totalMinutes / 60
    let remainingMinutes = totalMinutes % 60
    let formattedHours = hours.formatted(.number.locale(locale))
    let formattedMinutes = remainingMinutes.formatted(.number.locale(locale))
    if hours == 0 {
      return "\(formattedMinutes)m"
    }
    if remainingMinutes == 0 {
      return "\(formattedHours)h"
    }
    return "\(formattedHours)h\(formattedMinutes)m"
  }

  private static func batteryStateOfCharge(
    _ stateOfCharge: Double?,
    unavailable: String,
    locale: Locale
  ) -> String {
    guard let stateOfCharge else { return unavailable }
    let percentage = stateOfCharge.formatted(
      .number.locale(locale).precision(.fractionLength(0))
    )
    return "\(percentage)%"
  }

  private static func safeChargingTimeAccessibility(
    minutes: Double?,
    unavailable: String,
    locale: Locale
  ) -> String {
    guard let minutes else { return unavailable }
    let formatter = DateComponentsFormatter()
    var calendar = Calendar.current
    calendar.locale = locale
    formatter.calendar = calendar
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .full
    formatter.zeroFormattingBehavior = [.dropLeading]
    return formatter.string(from: minutes * 60) ?? unavailable
  }

  private static func batteryIcon(stateOfCharge: Double?) -> String {
    guard let stateOfCharge else { return "batteryblock" }
    switch stateOfCharge {
    case ..<13: return "battery.0percent"
    case ..<38: return "battery.25percent"
    case ..<63: return "battery.50percent"
    case ..<88: return "battery.75percent"
    default: return "battery.100percent"
    }
  }

}

private struct EVChargingExplanationResolver {
  private static let homeBatteryReserve = 15.0
  private static let daytimeRestartThreshold = 20.0

  let decision: HomeAssistantEVChargingDecision
  let chargingMode: HomeAssistantEVChargingMode
  let date: Date
  let calendar: Calendar
  let copy: EVChargingCopy
  let locale: Locale

  var text: String {
    guard decision.isChargingDesired != nil else {
      return copy.chargingDecisionUnavailable
    }
    if chargingMode == .off {
      return copy.chargingSwitchedOff
    }
    guard let price = decision.currentPriceDollarsPerKilowattHour else {
      return copy.electricityPriceUnavailable
    }
    if price >= 0.40 {
      return copy.priceTooHigh(price: price, locale: locale)
    }
    guard let priceAllowsCharging = decision.priceAllowsCharging else {
      return copy.electricityPriceUnavailable
    }
    if !priceAllowsCharging {
      return price < 0.35
        ? copy.chargingDecisionUpdating
        : copy.waitingForLowerPrice(price: price, locale: locale)
    }
    if chargingMode == .charging {
      return decision.isChargingDesired == true
        ? copy.chargingRequested
        : copy.chargingDecisionUnavailable
    }
    return smartChargingText
  }

  private var smartChargingText: String {
    guard let stateOfCharge = decision.batteryStateOfCharge else {
      return copy.homeBatteryUnavailable
    }
    let hour = calendar.component(.hour, from: date)
    if hour >= 16, hour < 21 {
      return decision.isChargingDesired == false
        ? copy.pausedForAfternoonPeak
        : copy.chargingDecisionUpdating
    }
    if hour >= 6, hour < 16 {
      return daytimeText(stateOfCharge: stateOfCharge)
    }
    return overnightText(stateOfCharge: stateOfCharge)
  }

  private func daytimeText(stateOfCharge: Double) -> String {
    if decision.isChargingDesired == true {
      return stateOfCharge >= Self.homeBatteryReserve
        ? copy.homeBatteryHasEnoughReserve
        : copy.chargingDecisionUpdating
    }
    return stateOfCharge <= Self.daytimeRestartThreshold
      ? copy.waitingForHomeBattery(
        restartThreshold: Self.daytimeRestartThreshold,
        stateOfCharge: stateOfCharge,
        locale: locale
      )
      : copy.chargingDecisionUpdating
  }

  private func overnightText(stateOfCharge: Double) -> String {
    if stateOfCharge <= Self.homeBatteryReserve {
      return copy.protectingHomeBatteryReserve(
        threshold: Self.homeBatteryReserve,
        locale: locale
      )
    }
    guard let safeMinutes = decision.overnightSafeChargingMinutes else {
      return copy.overnightForecastUnavailable
    }
    let remainingMinutes = minutesUntilSixAM
    if decision.isChargingDesired == true {
      return safeMinutes >= remainingMinutes
        ? copy.enoughEnergyUntilMorning
        : copy.chargingDecisionUpdating
    }
    return safeMinutes < remainingMinutes + 10
      ? copy.waitingForSafeOvernightStart
      : copy.chargingDecisionUpdating
  }

  private var minutesUntilSixAM: Double {
    let nextSixAM =
      calendar.nextDate(
        after: date,
        matching: DateComponents(hour: 6),
        matchingPolicy: .nextTime
      ) ?? date
    return max(nextSixAM.timeIntervalSince(date) / 60, 0)
  }
}

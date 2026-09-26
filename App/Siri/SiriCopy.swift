import AppIntents
import Foundation

struct SiriCopy {
  let mode: BruceMode

  static var current: Self {
    let preference = UserDefaults.standard.object(forKey: BruceMode.storageKey)
    if let fullBruce = preference as? Bool {
      return Self(mode: fullBruce ? .full : .standard)
    }
    return Self(mode: (preference as? String).flatMap(BruceMode.init(rawValue:)) ?? .standard)
  }

  func solarGeneration(_ kilowatts: Double, locale: Locale = .current) -> String {
    text("siri.solar.response").replacingOccurrences(
      of: "%@", with: power(kilowatts, locale: locale))
  }

  func electricityUsage(_ kilowatts: Double, locale: Locale = .current) -> String {
    text("siri.usage.response").replacingOccurrences(
      of: "%@", with: power(kilowatts, locale: locale))
  }

  func batteryLevel(_ percentage: Double, locale: Locale = .current) -> String {
    let value = percentage.formatted(.number.locale(locale).precision(.fractionLength(0...2)))
    return text("siri.battery.response").replacingOccurrences(of: "%@", with: value)
  }

  func chargerMode(_ chargerMode: EVChargerMode, didChange: Bool = false) -> String {
    let key: String.LocalizationValue = didChange ? "siri.setMode.response" : "siri.mode.response"
    return text(key).replacingOccurrences(of: "%@", with: modeName(chargerMode))
  }

  func chargerStatus(_ activity: HomeAssistantEVChargingActivity) -> String {
    let status = HomeAssistantEVActivityPresentation(activity: activity, mode: mode).text
    return text("siri.status.response").replacingOccurrences(of: "%@", with: status)
  }

  func error(_ error: BruceSiriError) -> String {
    switch error {
    case .unavailable: text("siri.error.unavailable")
    case .connectionUnavailable: text("siri.error.connectionUnavailable")
    case .signInRequired: text("siri.error.signInRequired")
    case .modeNotConfirmed: text("siri.error.modeNotConfirmed")
    }
  }

  func dialog(_ text: String) -> IntentDialog {
    IntentDialog("\(text)")
  }

  private func modeName(_ chargerMode: EVChargerMode) -> String {
    switch chargerMode {
    case .off: text("siri.mode.off.spoken")
    case .smart: text("siri.mode.smart.spoken")
    case .charging: text("siri.mode.on.spoken")
    }
  }

  private func power(_ kilowatts: Double, locale: Locale) -> String {
    Measurement(value: kilowatts, unit: UnitPower.kilowatts).formatted(
      .measurement(
        width: .wide, usage: .asProvided,
        numberFormatStyle: .number.precision(.fractionLength(0...2))
      )
      .locale(locale)
    )
  }

  private func text(_ key: String.LocalizationValue) -> String {
    BruceCopy(mode: mode).text(.localized(key))
  }
}

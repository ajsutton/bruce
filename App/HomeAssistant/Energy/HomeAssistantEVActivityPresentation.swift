import SwiftUI

struct HomeAssistantEVActivityPresentation {
  let icon: String
  let statusIcon: String
  let text: String
  let accessibilityText: String
  let color: Color

  init(
    activity: HomeAssistantEVChargingActivity,
    mode: BruceMode,
    locale: Locale = .current
  ) {
    let values = Self.values(for: activity, locale: locale)
    icon = values.icon
    statusIcon = values.statusIcon
    if mode.isFullBruce {
      text = Self.fullBruceText(for: activity, locale: locale)
      accessibilityText = text
    } else {
      text = values.text
      accessibilityText = values.text
    }
    color = values.color
  }

  private static func values(
    for activity: HomeAssistantEVChargingActivity,
    locale: Locale
  ) -> Values {
    switch activity {
    case .unavailable:
      Values("bolt.car", "questionmark.circle", "Charger status unavailable", .secondary)
    case .notPluggedIn:
      Values("bolt.car", "powerplug.portrait", "Not plugged in", .secondary)
    case .connected:
      Values("bolt.car", "checkmark.circle", "Connected — ready", .secondary)
    case .waitingForVehicle:
      Values("bolt.car", "hourglass", "Waiting for vehicle", .secondary)
    case .charging(let powerWatts):
      Values(
        "bolt.car.fill",
        "bolt.fill",
        chargingText(powerWatts: powerWatts, locale: locale),
        .green
      )
    case .complete:
      Values("checkmark.circle.fill", "checkmark.circle.fill", "Charge complete", .green)
    case .paused(let reason):
      Values("pause.circle.fill", "pause.circle.fill", pausedText(reason: reason), .orange)
    case .switchedOff:
      Values("bolt.car", "power", "Charging switched off", .secondary)
    }
  }

  private static func chargingText(powerWatts: Double?, locale: Locale) -> String {
    guard let powerWatts else {
      return "Charging"
    }
    return "Charging · \(formattedPower(powerWatts, locale: locale))"
  }

  private static func pausedText(
    reason: HomeAssistantEVChargingActivity.PauseReason?
  ) -> String {
    switch reason {
    case .electricityPrice:
      "Paused — electricity price too high"
    case .homeBattery:
      "Paused — protecting home battery"
    case nil:
      "Charging paused"
    }
  }

  private static func fullBruceText(
    for activity: HomeAssistantEVChargingActivity,
    locale: Locale
  ) -> String {
    switch activity {
    case .unavailable:
      "Charger status unavailable"
    case .notPluggedIn:
      "Not plugged in. Can’t charge fresh air."
    case .connected:
      "Plugged in and ready to rip"
    case .waitingForVehicle:
      "Waiting on the car"
    case .charging(let powerWatts):
      "\(chargingText(powerWatts: powerWatts, locale: locale)) — giving it the berries"
    case .complete:
      "Charged. Good as gold."
    case .paused:
      "Taking a breather"
    case .switchedOff:
      "Off. Charger’s knocked off."
    }
  }

  private static func formattedPower(_ powerWatts: Double, locale: Locale) -> String {
    let kilowatts = powerWatts / 1_000
    return
      "\(kilowatts.formatted(.number.locale(locale).precision(.fractionLength(1)))) kW"
  }
}

private struct Values {
  let icon: String
  let statusIcon: String
  let text: String
  let color: Color

  init(_ icon: String, _ statusIcon: String, _ text: String, _ color: Color) {
    self.icon = icon
    self.statusIcon = statusIcon
    self.text = text
    self.color = color
  }
}

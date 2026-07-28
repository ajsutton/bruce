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
    let copy = EVChargingCopy(mode: mode)
    let values = Self.values(for: activity, copy: copy, locale: locale)
    icon = values.icon
    statusIcon = values.statusIcon
    text = values.text
    accessibilityText = values.text
    color = values.color
  }

  private static func values(
    for activity: HomeAssistantEVChargingActivity,
    copy: EVChargingCopy,
    locale: Locale
  ) -> Values {
    switch activity {
    case .unavailable:
      Values("bolt.car", "questionmark.circle", copy.chargerStatusUnavailable, .secondary)
    case .notPluggedIn:
      Values("bolt.car", "powerplug.portrait", copy.notPluggedIn, .secondary)
    case .connected:
      Values("bolt.car", "checkmark.circle", copy.connectedReady, .secondary)
    case .waitingForVehicle:
      Values("bolt.car", "hourglass", copy.waitingForVehicle, .secondary)
    case .charging(let powerWatts):
      Values(
        "bolt.car.fill",
        "bolt.fill",
        copy.charging(powerWatts: powerWatts, locale: locale),
        .green
      )
    case .complete:
      Values("checkmark.circle.fill", "checkmark.circle.fill", copy.chargeComplete, .green)
    case .paused(let reason):
      Values(
        "pause.circle.fill",
        "pause.circle.fill",
        pausedText(reason: reason, copy: copy),
        .orange
      )
    case .switchedOff:
      Values("bolt.car", "power", copy.chargingSwitchedOff, .secondary)
    }
  }

  private static func pausedText(
    reason: HomeAssistantEVChargingActivity.PauseReason?,
    copy: EVChargingCopy
  ) -> String {
    switch reason {
    case .electricityPrice:
      copy.pausedForPrice
    case .homeBattery:
      copy.pausedForBattery
    case nil:
      copy.chargingPaused
    }
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

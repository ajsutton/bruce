import SwiftUI

struct AirConditionerModePresentation {
  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode
  let showsName: Bool
  let style: AirConditionerCardStyle

  private var copy: TemperatureCopy {
    TemperatureCopy(mode: mode)
  }

  var label: String {
    switch reading.operatingMode {
    case .automatic:
      copy.automatic
    case .cooling:
      copy.cooling
    case .drying:
      copy.drying
    case .fanOnly:
      copy.fanOnly
    case .heating:
      copy.heating
    case .off:
      copy.powerOff
    case .active:
      copy.powerOn
    case .unavailable:
      copy.unavailable
    }
  }

  var statusLabel: String {
    if showsName {
      return copy.mode(name: reading.name)
    }
    return copy.mode
  }

  var accessibilityLabel: String {
    switch reading.operatingMode {
    case .automatic:
      copy.automaticAccessibility
    case .cooling:
      copy.coolingAccessibility
    case .drying:
      copy.dryingAccessibility
    case .fanOnly:
      copy.fanOnlyAccessibility
    case .heating:
      copy.heatingAccessibility
    case .off:
      copy.powerOffAccessibility
    case .active:
      copy.powerOnAccessibility
    case .unavailable:
      copy.unavailableAccessibility
    }
  }

  func powerAccessibilityLabel(isControlling: Bool) -> String {
    if isControlling {
      return copy.updating(name: reading.name)
    }
    switch reading.powerState {
    case .poweredOn:
      return copy.turnOff(name: reading.name)
    case .off:
      return copy.turnOn(name: reading.name)
    case .unavailable:
      return copy.powerUnavailable(name: reading.name)
    }
  }

  var foreground: AnyShapeStyle {
    switch reading.operatingMode {
    case .off:
      style.secondaryForeground
    case .unavailable:
      AnyShapeStyle(Color.red)
    default:
      AnyShapeStyle(style.accentForeground)
    }
  }

  var iconForeground: Color {
    switch reading.operatingMode {
    case .off:
      mode.isFullBruce ? Color.white.opacity(0.76) : Color.secondary
    case .unavailable:
      mode.isFullBruce ? Color.white : Color.red
    default:
      style.iconForeground
    }
  }

  var iconBackground: Color {
    switch reading.operatingMode {
    case .off:
      if mode.isFullBruce {
        return Color.white.opacity(0.14)
      }
      return Color.secondary.opacity(0.12)
    case .unavailable:
      if mode.isFullBruce {
        return Color.red
      }
      return Color.red.opacity(0.12)
    default:
      return style.iconBackground
    }
  }

  var symbol: String {
    switch reading.operatingMode {
    case .automatic:
      "arrow.trianglehead.2.clockwise.rotate.90"
    case .cooling:
      "snowflake"
    case .drying:
      "drop.fill"
    case .fanOnly:
      "fan.fill"
    case .heating:
      "flame.fill"
    case .off:
      "power"
    case .active:
      "air.conditioner.horizontal"
    case .unavailable:
      "exclamationmark.triangle.fill"
    }
  }
}

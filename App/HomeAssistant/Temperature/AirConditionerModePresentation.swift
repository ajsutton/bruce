import SwiftUI

struct AirConditionerModePresentation {
  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode
  let showsName: Bool
  let style: AirConditionerCardStyle

  var label: String {
    switch reading.operatingMode {
    case .automatic:
      "Auto"
    case .cooling:
      "Cool"
    case .drying:
      "Dry"
    case .fanOnly:
      "Fan"
    case .heating:
      "Heat"
    case .off:
      "Off"
    case .active:
      "On"
    case .unavailable:
      "Unavailable"
    }
  }

  var statusLabel: String {
    if showsName {
      return "\(reading.name) mode"
    }
    return mode.isFullBruce ? "Air-con mode" : "Mode"
  }

  func powerAccessibilityLabel(isControlling: Bool) -> String {
    if isControlling {
      return "Updating \(reading.name)"
    }
    switch reading.powerState {
    case .poweredOn:
      return "Turn off \(reading.name)"
    case .off:
      return "Turn on \(reading.name)"
    case .unavailable:
      return "\(reading.name) power unavailable"
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

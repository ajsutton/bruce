import SwiftUI

struct TemperatureCardStyle {
  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode

  var cardBackground: AnyShapeStyle {
    if reading.powerState == .poweredOn {
      return AnyShapeStyle(mode.foregroundColor)
    }
    if mode.isFullBruce {
      return AnyShapeStyle(Color(red: 0.00, green: 0.25, blue: 0.18))
    }
    return AnyShapeStyle(.background)
  }

  var primaryForeground: AnyShapeStyle {
    if reading.powerState == .poweredOn {
      return AnyShapeStyle(mode.backgroundColor)
    }
    if mode.isFullBruce {
      return AnyShapeStyle(mode.foregroundColor)
    }
    return AnyShapeStyle(.primary)
  }

  var secondaryForeground: AnyShapeStyle {
    if reading.powerState == .poweredOn {
      return AnyShapeStyle(mode.backgroundColor)
    }
    if mode.isFullBruce {
      return AnyShapeStyle(Color.white.opacity(0.78))
    }
    return AnyShapeStyle(.secondary)
  }

  var emphasizedForeground: Color {
    if reading.powerState == .poweredOn {
      return mode.backgroundColor
    }
    return mode.isFullBruce ? mode.foregroundColor : mode.accentColor
  }

  var iconForeground: Color {
    switch reading.powerState {
    case .poweredOn:
      mode.foregroundColor
    case .off:
      mode.isFullBruce ? Color.white.opacity(0.76) : Color.secondary
    case .unavailable:
      mode.isFullBruce ? Color.white : Color.red
    }
  }

  var iconBackground: Color {
    switch reading.powerState {
    case .poweredOn:
      return mode.backgroundColor
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
    }
  }

  var powerStateForeground: AnyShapeStyle {
    switch reading.powerState {
    case .poweredOn:
      AnyShapeStyle(emphasizedForeground)
    case .off, .unavailable:
      secondaryForeground
    }
  }

  var cardBorder: Color {
    if reading.powerState == .poweredOn {
      return mode.backgroundColor.opacity(0.28)
    }
    return mode.isFullBruce ? mode.foregroundColor.opacity(0.22) : .clear
  }

  var dividerColor: Color {
    if reading.powerState == .poweredOn {
      return mode.backgroundColor.opacity(0.22)
    }
    return mode.isFullBruce ? Color.white.opacity(0.22) : .clear
  }

  var controlTint: Color {
    if reading.powerState == .poweredOn {
      return mode.backgroundColor
    }
    return mode.accentColor
  }
}

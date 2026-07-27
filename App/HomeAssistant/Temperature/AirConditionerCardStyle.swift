import SwiftUI

struct AirConditionerCardStyle {
  let mode: BruceMode
  let colorScheme: ColorScheme

  var primaryForeground: AnyShapeStyle {
    if mode.isFullBruce {
      return AnyShapeStyle(Color.white)
    }
    return colorScheme == .dark
      ? AnyShapeStyle(.primary)
      : AnyShapeStyle(mode.foregroundColor)
  }

  var secondaryForeground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color.white.opacity(0.76))
      : AnyShapeStyle(.secondary)
  }

  var accentForeground: Color {
    mode.accentColor
  }

  var iconForeground: Color {
    if mode.isFullBruce {
      return mode.backgroundColor
    }
    return colorScheme == .dark ? mode.backgroundColor : mode.foregroundColor
  }

  var iconBackground: Color {
    if mode.isFullBruce {
      return mode.accentColor
    }
    return colorScheme == .dark
      ? mode.foregroundColor.opacity(0.72)
      : Color.white.opacity(0.82)
  }

  var cardBackground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color(red: 0.00, green: 0.25, blue: 0.18))
      : AnyShapeStyle(.background)
  }

  var cardTint: AnyShapeStyle {
    if mode.isFullBruce {
      return AnyShapeStyle(
        LinearGradient(
          colors: [Color.white.opacity(0.06), .clear],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    }
    return AnyShapeStyle(
      LinearGradient(
        colors: [
          mode.backgroundColor.opacity(colorScheme == .dark ? 0.12 : 0.72),
          .clear,
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
    )
  }

  var borderColor: Color {
    if mode.isFullBruce {
      return mode.accentColor.opacity(0.28)
    }
    return colorScheme == .dark
      ? Color.white.opacity(0.08)
      : mode.foregroundColor.opacity(0.08)
  }
}

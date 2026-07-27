import SwiftUI

struct HomeAssistantAirConditionerCard: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let reading: HomeAssistantTemperatureReading
  let averageValue: Double?
  let mode: BruceMode
  let showsName: Bool

  init(
    reading: HomeAssistantTemperatureReading,
    averageValue: Double?,
    mode: BruceMode,
    showsName: Bool = false
  ) {
    self.reading = reading
    self.averageValue = averageValue
    self.mode = mode
    self.showsName = showsName
  }

  private var style: AirConditionerCardStyle {
    AirConditionerCardStyle(mode: mode, colorScheme: colorScheme)
  }

  private var modePresentation: AirConditionerModePresentation {
    AirConditionerModePresentation(
      reading: reading,
      mode: mode,
      showsName: showsName,
      style: style
    )
  }

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        stackedLayout
      } else {
        ViewThatFits(in: .horizontal) {
          rowLayout(.spacious)
          rowLayout(.condensed)
          stackedLayout
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background {
      RoundedRectangle(cornerRadius: 20)
        .fill(style.cardBackground)
      RoundedRectangle(cornerRadius: 20)
        .fill(style.cardTint)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(style.borderColor, lineWidth: 1)
    }
    .shadow(
      color: .black.opacity(mode.isFullBruce ? 0.22 : 0.1),
      radius: 14,
      y: 5
    )
    .accessibilityElement(children: .combine)
  }

  private func rowLayout(_ density: AirConditionerCardDensity) -> some View {
    HStack(spacing: density.spacing) {
      status(isCondensed: density == .condensed)
        .frame(
          minWidth: density.statusMinimumWidth,
          maxWidth: density.statusMaximumWidth,
          alignment: .leading
        )

      cardDivider

      temperature(
        label: averageLabel,
        value: averageValue,
        foreground: style.primaryForeground,
        isCondensed: density == .condensed
      )
      .frame(minWidth: density.temperatureMinimumWidth, alignment: .leading)
      .fixedSize(horizontal: true, vertical: false)

      cardDivider

      temperature(
        label: "Target",
        value: reading.targetValue,
        foreground: AnyShapeStyle(style.accentForeground),
        isCondensed: density == .condensed
      )
      .frame(minWidth: density.temperatureMinimumWidth, alignment: .leading)
      .fixedSize(horizontal: true, vertical: false)
    }
    .frame(maxWidth: .infinity, minHeight: density.minimumHeight)
  }

  private var stackedLayout: some View {
    VStack(alignment: .leading, spacing: 18) {
      status(isCondensed: false)
      cardDivider
      temperature(
        label: averageLabel,
        value: averageValue,
        foreground: style.primaryForeground,
        isCondensed: false
      )
      cardDivider
      temperature(
        label: "Target",
        value: reading.targetValue,
        foreground: AnyShapeStyle(style.accentForeground),
        isCondensed: false
      )
    }
  }

  private func status(isCondensed: Bool) -> some View {
    let iconSize: CGFloat = isCondensed ? 40 : 60

    return HStack(spacing: isCondensed ? 6 : 14) {
      Image(systemName: modePresentation.symbol)
        .font(.system(size: isCondensed ? 20 : 28, weight: .semibold))
        .foregroundStyle(modePresentation.iconForeground)
        .frame(width: iconSize, height: iconSize)
        .background(modePresentation.iconBackground, in: Circle())
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(modePresentation.statusLabel)
          .font(isCondensed ? .caption : .subheadline)
          .foregroundStyle(style.secondaryForeground)

        Text(modePresentation.label)
          .font(isCondensed ? .subheadline.weight(.semibold) : .title2.weight(.semibold))
          .foregroundStyle(modePresentation.foreground)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
  }

  private func temperature(
    label: String,
    value: Double?,
    foreground: AnyShapeStyle,
    isCondensed: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(isCondensed ? .caption : .subheadline)
        .foregroundStyle(style.secondaryForeground)

      HStack(alignment: .firstTextBaseline, spacing: 2) {
        if let value {
          Text(value, format: .number.precision(.fractionLength(1)))
          if let unit = reading.unit {
            Text(unit)
              .font(isCondensed ? .body : .title2)
          }
        } else {
          Text("—")
            .accessibilityLabel("Unavailable")
        }
      }
      .font(
        .system(
          isCondensed ? .title2 : .largeTitle,
          design: .rounded,
          weight: .medium
        )
      )
      .foregroundStyle(foreground)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.8)
    }
  }

  private var cardDivider: some View {
    Divider()
      .overlay(mode.isFullBruce ? Color.white.opacity(0.22) : .clear)
  }

  private var averageLabel: String {
    showsName ? "House avg." : "Average"
  }
}

private struct AirConditionerModePresentation {
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

private enum AirConditionerCardDensity {
  case spacious
  case condensed

  var spacing: CGFloat {
    self == .spacious ? 12 : 6
  }

  var statusMinimumWidth: CGFloat {
    self == .spacious ? 180 : 144
  }

  var statusMaximumWidth: CGFloat {
    self == .spacious ? .infinity : 144
  }

  var temperatureMinimumWidth: CGFloat {
    self == .spacious ? 96 : 68
  }

  var minimumHeight: CGFloat {
    self == .spacious ? 76 : 68
  }
}

private struct AirConditionerCardStyle {
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

import SwiftUI

struct HomeAssistantTemperatureCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode

  private var cardBackground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color(red: 0.00, green: 0.25, blue: 0.18))
      : AnyShapeStyle(.background)
  }

  private var primaryForeground: AnyShapeStyle {
    mode.isFullBruce ? AnyShapeStyle(mode.foregroundColor) : AnyShapeStyle(.primary)
  }

  private var secondaryForeground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color.white.opacity(0.78))
      : AnyShapeStyle(.secondary)
  }

  private var emphasizedForeground: Color {
    mode.isFullBruce ? mode.foregroundColor : mode.accentColor
  }

  private var iconForeground: Color {
    mode.isFullBruce ? mode.backgroundColor : mode.foregroundColor
  }

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize
        || dynamicTypeSize == .xLarge
        || dynamicTypeSize == .xxLarge
        || dynamicTypeSize == .xxxLarge
      {
        stackedLayout
      } else if horizontalSizeClass == .compact {
        ViewThatFits(in: .horizontal) {
          rowLayout(.condensed)
          stackedLayout
        }
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
    .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(
          mode.isFullBruce ? mode.foregroundColor.opacity(0.22) : .clear,
          lineWidth: 1
        )
    }
    .shadow(
      color: .black.opacity(mode.isFullBruce ? 0.2 : 0.1),
      radius: 10,
      y: 4
    )
    .accessibilityElement(children: .combine)
  }

  private func rowLayout(_ density: TemperatureRowDensity) -> some View {
    HStack(spacing: density.spacing) {
      location(isCondensed: density == .condensed)
        .frame(
          minWidth: density.locationMinimumWidth,
          maxWidth: density.locationMaximumWidth,
          alignment: .leading
        )
      cardDivider
      currentTemperature(isCondensed: density == .condensed)
        .frame(minWidth: density.temperatureMinimumWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
      cardDivider
      targetTemperature(isCondensed: density == .condensed)
        .frame(minWidth: density.temperatureMinimumWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }
    .frame(maxWidth: .infinity, minHeight: density.minimumHeight)
  }

  private var stackedLayout: some View {
    VStack(alignment: .leading, spacing: 16) {
      location(isCondensed: false)
      cardDivider
      currentTemperature(isCondensed: false)
      cardDivider
      targetTemperature(isCondensed: false)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var cardDivider: some View {
    Divider()
      .overlay(mode.isFullBruce ? Color.white.opacity(0.22) : .clear)
  }

  private func location(isCondensed: Bool) -> some View {
    let iconSize: CGFloat = isCondensed ? 40 : 52

    return HStack(spacing: isCondensed ? 6 : 12) {
      HomeAssistantTemperatureIconView(identifier: reading.icon)
        .foregroundStyle(iconForeground)
        .frame(width: iconSize, height: iconSize)
        .background(
          mode.isFullBruce ? mode.foregroundColor : mode.backgroundColor,
          in: RoundedRectangle(cornerRadius: isCondensed ? 12 : 14)
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        Text(reading.name)
          .font(isCondensed ? .subheadline.weight(.semibold) : .headline)
          .foregroundStyle(primaryForeground)
          .lineLimit(isCondensed ? 2 : nil)

        Text(powerStateLabel)
          .font(.caption)
          .foregroundStyle(powerStateForeground)
      }
    }
  }

  private func currentTemperature(isCondensed: Bool) -> some View {
    temperature(
      label: "Current",
      value: reading.value,
      foreground: primaryForeground,
      isCondensed: isCondensed
    )
  }

  private func targetTemperature(isCondensed: Bool) -> some View {
    temperature(
      label: "Target",
      value: reading.targetValue,
      foreground: AnyShapeStyle(emphasizedForeground),
      isCondensed: isCondensed
    )
  }

  private func temperature(
    label: String,
    value: Double?,
    foreground: AnyShapeStyle,
    isCondensed: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(secondaryForeground)

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
    }
  }

  private var powerStateLabel: String {
    switch reading.powerState {
    case .poweredOn:
      "On"
    case .off:
      "Off"
    case .unavailable:
      "Unavailable"
    }
  }

  private var powerStateForeground: AnyShapeStyle {
    switch reading.powerState {
    case .poweredOn:
      AnyShapeStyle(emphasizedForeground)
    case .off, .unavailable:
      secondaryForeground
    }
  }
}

private enum TemperatureRowDensity {
  case spacious
  case condensed

  var spacing: CGFloat {
    self == .spacious ? 12 : 6
  }

  var locationMinimumWidth: CGFloat {
    self == .spacious ? 180 : 144
  }

  var locationMaximumWidth: CGFloat {
    self == .spacious ? .infinity : 144
  }

  var temperatureMinimumWidth: CGFloat {
    self == .spacious ? 96 : 68
  }

  var minimumHeight: CGFloat {
    self == .spacious ? 76 : 68
  }
}

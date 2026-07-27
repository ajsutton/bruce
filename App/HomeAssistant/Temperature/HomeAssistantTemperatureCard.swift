import SwiftUI

struct HomeAssistantTemperatureCard: View {
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
    ViewThatFits(in: .horizontal) {
      compactLayout
      stackedLayout
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

  private var compactLayout: some View {
    HStack(spacing: 12) {
      location
        .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
      cardDivider
      currentTemperature
        .fixedSize(horizontal: true, vertical: false)
      cardDivider
      targetTemperature
        .fixedSize(horizontal: true, vertical: false)
    }
    .frame(maxWidth: .infinity, minHeight: 76)
  }

  private var stackedLayout: some View {
    VStack(alignment: .leading, spacing: 16) {
      location
      cardDivider
      currentTemperature
      cardDivider
      targetTemperature
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var cardDivider: some View {
    Divider()
      .overlay(mode.isFullBruce ? Color.white.opacity(0.22) : .clear)
  }

  private var location: some View {
    HStack(spacing: 12) {
      HomeAssistantTemperatureIconView(identifier: reading.icon)
        .foregroundStyle(iconForeground)
        .frame(width: 52, height: 52)
        .background(
          mode.isFullBruce ? mode.foregroundColor : mode.backgroundColor,
          in: RoundedRectangle(cornerRadius: 14)
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        Text(reading.name)
          .font(.headline)
          .foregroundStyle(primaryForeground)

        Text(powerStateLabel)
          .font(.caption)
          .foregroundStyle(powerStateForeground)
      }
    }
  }

  private var currentTemperature: some View {
    temperature(
      label: "Current",
      value: reading.value,
      foreground: primaryForeground
    )
  }

  private var targetTemperature: some View {
    temperature(
      label: "Target",
      value: reading.targetValue,
      foreground: AnyShapeStyle(emphasizedForeground)
    )
  }

  private func temperature(
    label: String,
    value: Double?,
    foreground: AnyShapeStyle
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(secondaryForeground)

      HStack(alignment: .firstTextBaseline, spacing: 2) {
        if let value {
          Text(value, format: .number.precision(.fractionLength(0...1)))
          if let unit = reading.unit {
            Text(unit)
              .font(.title2)
          }
        } else {
          Text("—")
            .accessibilityLabel("Unavailable")
        }
      }
      .font(.system(.largeTitle, design: .rounded, weight: .medium))
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

import SwiftUI

struct HomeAssistantTemperatureCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode
  let showsControl: Bool
  let isControlEnabled: Bool
  let isControlling: Bool
  let showsTargetControl: Bool
  let targetValueFractionLength: Int
  let setPower: (Bool) -> Void
  let setTargetValue: @MainActor @Sendable (Double) -> Void

  init(
    reading: HomeAssistantTemperatureReading,
    mode: BruceMode,
    showsControl: Bool = false,
    isControlEnabled: Bool = false,
    isControlling: Bool = false,
    showsTargetControl: Bool = false,
    targetValueFractionLength: Int = 1,
    setPower: @escaping (Bool) -> Void = { _ in },
    setTargetValue: @escaping @MainActor @Sendable (Double) -> Void = { _ in }
  ) {
    self.reading = reading
    self.mode = mode
    self.showsControl = showsControl
    self.isControlEnabled = isControlEnabled
    self.isControlling = isControlling
    self.showsTargetControl = showsTargetControl
    self.targetValueFractionLength = targetValueFractionLength
    self.setPower = setPower
    self.setTargetValue = setTargetValue
  }

  private var style: TemperatureCardStyle {
    TemperatureCardStyle(reading: reading, mode: mode)
  }

  @ViewBuilder
  var body: some View {
    if showsControl, showsTargetControl {
      adjustableCard
    } else if showsControl {
      Button {
        setPower(reading.powerState == .off)
      } label: {
        card
      }
      .buttonStyle(.plain)
      .disabled(!isControlEnabled || isControlling)
      .accessibilityLabel(powerAccessibilityLabel)
      .accessibilityValue(powerAccessibilityValue)
    } else {
      card
        .accessibilityElement(children: .combine)
    }
  }

  private var card: some View {
    cardSurface {
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
  }

  fileprivate func cardSurface<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(style.cardBackground, in: RoundedRectangle(cornerRadius: 20))
      .overlay {
        RoundedRectangle(cornerRadius: 20)
          .stroke(
            style.cardBorder,
            lineWidth: 1
          )
      }
      .shadow(
        color: .black.opacity(mode.isFullBruce ? 0.2 : 0.1),
        radius: 10,
        y: 4
      )
      .contentShape(RoundedRectangle(cornerRadius: 20))
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
      .overlay(style.dividerColor)
  }

  private func location(isCondensed: Bool) -> some View {
    let iconSize: CGFloat = isCondensed ? 40 : 52

    return HStack(spacing: isCondensed ? 6 : 12) {
      Group {
        if isControlling {
          ProgressView()
            .controlSize(isCondensed ? .small : .regular)
        } else {
          HomeAssistantTemperatureIconView(identifier: reading.icon)
        }
      }
      .foregroundStyle(style.iconForeground)
      .frame(width: iconSize, height: iconSize)
      .background(
        style.iconBackground,
        in: RoundedRectangle(cornerRadius: isCondensed ? 12 : 14)
      )
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        Text(reading.name)
          .font(isCondensed ? .subheadline.weight(.semibold) : .headline)
          .foregroundStyle(style.primaryForeground)
          .lineLimit(isCondensed ? 2 : nil)

        Text(powerStateLabel)
          .font(.caption)
          .foregroundStyle(style.powerStateForeground)
      }
    }
  }

  private func currentTemperature(isCondensed: Bool) -> some View {
    temperature(
      label: "Current",
      value: reading.value,
      foreground: style.primaryForeground,
      isCondensed: isCondensed
    )
  }

  @ViewBuilder
  private func targetTemperature(isCondensed: Bool) -> some View {
    temperature(
      label: "Target",
      value: reading.targetValue,
      foreground: AnyShapeStyle(style.emphasizedForeground),
      isCondensed: isCondensed,
      fractionLength: targetValueFractionLength
    )
    .padding(.trailing, showsTargetControl ? targetControlClearance : 0)
  }

  private func temperature(
    label: String,
    value: Double?,
    foreground: AnyShapeStyle,
    isCondensed: Bool,
    fractionLength: Int = 1
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(style.secondaryForeground)

      HStack(alignment: .firstTextBaseline, spacing: 2) {
        if let value {
          Text(value, format: .number.precision(.fractionLength(fractionLength)))
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

}

extension HomeAssistantTemperatureCard {
  @ViewBuilder
  fileprivate var adjustableCard: some View {
    if dynamicTypeSize.isAccessibilitySize
      || dynamicTypeSize == .xLarge
      || dynamicTypeSize == .xxLarge
      || dynamicTypeSize == .xxxLarge
    {
      powerCard(usesBottomTargetControlAlignment: true) {
        stackedLayout
      }
    } else if horizontalSizeClass == .compact {
      ViewThatFits(in: .horizontal) {
        powerCard(usesBottomTargetControlAlignment: false) {
          rowLayout(.condensed)
        }
        powerCard(usesBottomTargetControlAlignment: true) {
          stackedLayout
        }
      }
    } else {
      ViewThatFits(in: .horizontal) {
        powerCard(usesBottomTargetControlAlignment: false) {
          rowLayout(.spacious)
        }
        powerCard(usesBottomTargetControlAlignment: false) {
          rowLayout(.condensed)
        }
        powerCard(usesBottomTargetControlAlignment: true) {
          stackedLayout
        }
      }
    }
  }

  fileprivate func powerCard<Content: View>(
    usesBottomTargetControlAlignment: Bool,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let targetControlAlignment: Alignment =
      usesBottomTargetControlAlignment ? .bottomTrailing : .trailing
    return Button {
      setPower(reading.powerState == .off)
    } label: {
      cardSurface(content: content)
    }
    .buttonStyle(.plain)
    .disabled(!isControlEnabled || isControlling)
    .accessibilityLabel(powerAccessibilityLabel)
    .accessibilityValue(powerAccessibilityValue)
    .overlay(alignment: targetControlAlignment) {
      ZoneTargetTemperatureControl(
        reading: reading,
        mode: mode,
        isEnabled: isControlEnabled,
        isControlling: isControlling,
        fractionLength: targetValueFractionLength,
        setTargetValue: setTargetValue
      )
      .padding(
        targetControlInsets(
          usesBottomTargetControlAlignment: usesBottomTargetControlAlignment
        )
      )
    }
  }

  fileprivate func targetControlInsets(
    usesBottomTargetControlAlignment: Bool
  ) -> EdgeInsets {
    EdgeInsets(
      top: usesBottomTargetControlAlignment ? 0 : 16,
      leading: 0,
      bottom: 16,
      trailing: 16
    )
  }

  fileprivate var targetControlClearance: CGFloat {
    #if os(iOS)
      104
    #else
      36
    #endif
  }

  fileprivate var powerStateLabel: String {
    switch reading.powerState {
    case .poweredOn:
      "On"
    case .off:
      "Off"
    case .unavailable:
      "Unavailable"
    }
  }

  fileprivate var powerAccessibilityLabel: String {
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

  fileprivate var powerAccessibilityValue: String {
    let currentValue = temperatureAccessibilityValue(
      reading.value,
      fractionLength: 1
    )
    let targetValue =
      reading.targetValue.map {
        temperatureAccessibilityValue(
          $0,
          fractionLength: targetValueFractionLength
        )
      } ?? "Unavailable"
    let progress = isControlling ? "Updating. " : ""
    return "\(progress)\(powerStateLabel). Current \(currentValue). Target \(targetValue)"
  }

  fileprivate func temperatureAccessibilityValue(
    _ value: Double,
    fractionLength: Int
  ) -> String {
    let formattedValue = value.formatted(
      .number.precision(.fractionLength(fractionLength))
    )
    return "\(formattedValue)\(reading.unit ?? "")"
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

import SwiftUI

struct HomeAssistantAirConditionerCard: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var isShowingModePicker = false

  let reading: HomeAssistantTemperatureReading
  let averageValue: Double?
  let mode: BruceMode
  let showsName: Bool
  let showsControls: Bool
  let isControlEnabled: Bool
  let isControlling: Bool
  let targetValueFractionLength: Int
  let setPower: (Bool) -> Void
  let setMode: (HomeAssistantTemperatureReading.ClimateMode) -> Void

  init(
    reading: HomeAssistantTemperatureReading,
    averageValue: Double?,
    mode: BruceMode,
    showsName: Bool = false,
    showsControls: Bool = false,
    isControlEnabled: Bool = false,
    isControlling: Bool = false,
    targetValueFractionLength: Int = 1,
    setPower: @escaping (Bool) -> Void = { _ in },
    setMode: @escaping (HomeAssistantTemperatureReading.ClimateMode) -> Void = { _ in }
  ) {
    self.reading = reading
    self.averageValue = averageValue
    self.mode = mode
    self.showsName = showsName
    self.showsControls = showsControls
    self.isControlEnabled = isControlEnabled
    self.isControlling = isControlling
    self.targetValueFractionLength = targetValueFractionLength
    self.setPower = setPower
    self.setMode = setMode
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
      } else if horizontalSizeClass == .compact {
        #if os(iOS)
          rowLayout(.condensed)
        #else
          ViewThatFits(in: .horizontal) {
            rowLayout(.condensed)
            stackedLayout
          }
        #endif
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
    .accessibilityElement(children: .contain)
    .onChange(of: isControlEnabled, dismissModePickerWhenDisabled)
    .onChange(of: isControlling, dismissModePickerWhenUpdating)
  }

  private func rowLayout(_ density: AirConditionerCardDensity) -> some View {
    HStack(spacing: density.spacing) {
      HStack(spacing: 0) {
        status(isCondensed: density == .condensed)
          .frame(
            minWidth: density.statusMinimumWidth,
            maxWidth: density.statusMaximumWidth,
            alignment: .leading
          )
        Spacer(minLength: 0)
      }

      cardDivider

      temperature(
        label: averageLabel,
        value: averageValue,
        foreground: style.primaryForeground,
        isCondensed: density == .condensed
      )
      .frame(
        minWidth: density.temperatureMinimumWidth,
        maxWidth: density.temperatureMaximumWidth,
        alignment: .leading
      )

      cardDivider

      temperature(
        label: "Target",
        value: reading.targetValue,
        foreground: AnyShapeStyle(style.accentForeground),
        isCondensed: density == .condensed,
        fractionLength: targetValueFractionLength
      )
      .frame(
        minWidth: density.temperatureMinimumWidth,
        maxWidth: density.temperatureMaximumWidth,
        alignment: .leading
      )
      .padding(.trailing, targetColumnTrailingClearance)
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
        isCondensed: false,
        fractionLength: targetValueFractionLength
      )
    }
  }

  private func status(isCondensed: Bool) -> some View {
    let iconSize: CGFloat = isCondensed ? 44 : 60

    return HStack(spacing: isCondensed ? 6 : 14) {
      powerControl(iconSize: iconSize, isCondensed: isCondensed)

      VStack(alignment: .leading, spacing: 3) {
        Text(modePresentation.statusLabel)
          .font(isCondensed ? .caption : .subheadline)
          .foregroundStyle(style.secondaryForeground)

        modeControl(isCondensed: isCondensed)
      }
    }
  }

  @ViewBuilder
  private func powerControl(iconSize: CGFloat, isCondensed: Bool) -> some View {
    if showsControls {
      Button {
        setPower(reading.powerState == .off)
      } label: {
        Group {
          if isControlling {
            ProgressView()
              .controlSize(isCondensed ? .small : .regular)
          } else {
            Image(systemName: modePresentation.symbol)
              .font(.system(size: isCondensed ? 20 : 28, weight: .semibold))
          }
        }
        .foregroundStyle(modePresentation.iconForeground)
        .frame(width: iconSize, height: iconSize)
        .background(modePresentation.iconBackground, in: Circle())
      }
      .buttonStyle(.plain)
      .disabled(!isControlEnabled || isControlling)
      .accessibilityLabel(
        modePresentation.powerAccessibilityLabel(isControlling: isControlling)
      )
    } else {
      Image(systemName: modePresentation.symbol)
        .font(.system(size: isCondensed ? 20 : 28, weight: .semibold))
        .foregroundStyle(modePresentation.iconForeground)
        .frame(width: iconSize, height: iconSize)
        .background(modePresentation.iconBackground, in: Circle())
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private func modeControl(isCondensed: Bool) -> some View {
    if showsControls, !reading.availableModes.isEmpty {
      Button {
        isShowingModePicker.toggle()
      } label: {
        HStack(spacing: 5) {
          modeText(isCondensed: isCondensed)
          Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
        }
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!isControlEnabled || isControlling)
      .popover(isPresented: $isShowingModePicker, arrowEdge: .top) {
        HomeAssistantClimateModePicker(
          modes: reading.availableModes,
          operatingMode: reading.operatingMode,
          isCondensed: isCondensed
        ) { selectedMode in
          isShowingModePicker = false
          setMode(selectedMode)
        }
        .presentationCompactAdaptation(.popover)
      }
      .accessibilityLabel(
        isControlling ? "Updating \(reading.name)" : "\(reading.name) mode"
      )
      .accessibilityValue(isControlling ? "In progress" : modePresentation.label)
    } else {
      modeText(isCondensed: isCondensed)
    }
  }

  private func modeText(isCondensed: Bool) -> some View {
    Text(modePresentation.label)
      .font(modeFont(isCondensed: isCondensed))
      .foregroundStyle(modePresentation.foreground)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
  }

}

extension HomeAssistantAirConditionerCard {
  fileprivate func temperature(
    label: String,
    value: Double?,
    foreground: AnyShapeStyle,
    isCondensed: Bool,
    fractionLength: Int = 1
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(isCondensed ? .caption : .subheadline)
        .foregroundStyle(style.secondaryForeground)
        .lineLimit(1)
        .minimumScaleFactor(0.6)

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
      .lineLimit(1)
      .minimumScaleFactor(0.5)
    }
  }

  fileprivate func modeFont(isCondensed: Bool) -> Font {
    isCondensed ? .subheadline.weight(.semibold) : .title2.weight(.semibold)
  }

  fileprivate var averageLabel: String {
    showsName ? "House avg." : "Average"
  }

  fileprivate var targetColumnTrailingClearance: CGFloat {
    #if os(iOS)
      16
    #else
      0
    #endif
  }

  fileprivate var cardDivider: some View {
    Divider()
      .overlay(mode.isFullBruce ? Color.white.opacity(0.22) : .clear)
  }

  fileprivate func dismissModePickerWhenDisabled(from _: Bool, to isEnabled: Bool) {
    if !isEnabled {
      isShowingModePicker = false
    }
  }

  fileprivate func dismissModePickerWhenUpdating(from _: Bool, to isUpdating: Bool) {
    if isUpdating {
      isShowingModePicker = false
    }
  }
}

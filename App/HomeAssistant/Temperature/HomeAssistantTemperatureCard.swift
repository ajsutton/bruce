import SwiftUI

struct HomeAssistantTemperatureCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode
  let showsControl: Bool
  let isControlEnabled: Bool
  let isControlling: Bool
  let isAdjustmentControlling: Bool
  let isLastKnown: Bool
  let showsAdjustmentControl: Bool
  let adjustmentFractionLength: Int
  let setPower: (Bool) -> Void
  let setAdjustmentValue: @Sendable (Double) -> Void

  init(
    reading: HomeAssistantTemperatureReading,
    mode: BruceMode,
    showsControl: Bool = false,
    isControlEnabled: Bool = false,
    isControlling: Bool = false,
    isAdjustmentControlling: Bool = false,
    isLastKnown: Bool = false,
    showsAdjustmentControl: Bool = false,
    adjustmentFractionLength: Int = 1,
    setPower: @escaping (Bool) -> Void = { _ in },
    setAdjustmentValue: @escaping @Sendable (Double) -> Void = { _ in }
  ) {
    self.reading = reading
    self.mode = mode
    self.showsControl = showsControl
    self.isControlEnabled = isControlEnabled
    self.isControlling = isControlling
    self.isAdjustmentControlling = isAdjustmentControlling
    self.isLastKnown = isLastKnown
    self.showsAdjustmentControl = showsAdjustmentControl
    self.adjustmentFractionLength = adjustmentFractionLength
    self.setPower = setPower
    self.setAdjustmentValue = setAdjustmentValue
  }

  private var style: TemperatureCardStyle {
    TemperatureCardStyle(reading: reading, mode: mode)
  }

  private var copy: TemperatureCopy {
    TemperatureCopy(mode: mode)
  }

  private var usesAdjustableCard: Bool {
    #if os(iOS)
      showsControl
    #else
      showsControl && showsAdjustmentControl
    #endif
  }

  @ViewBuilder
  var body: some View {
    if usesAdjustableCard {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.name)
        .accessibilityValue(powerAccessibilityValue)
    }
  }

  private var card: some View {
    cardSurface {
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
      HStack(spacing: 0) {
        location(isCondensed: density == .condensed)
          .frame(
            minWidth: density.locationMinimumWidth(
              isCompact: horizontalSizeClass == .compact
            ),
            maxWidth: density.locationMaximumWidth(
              isCompact: horizontalSizeClass == .compact
            ),
            alignment: .leading
          )
        Spacer(minLength: 0)
      }
      cardDivider
      if !reading.isSensorlessZone {
        currentTemperature(isCondensed: density == .condensed)
          .frame(
            minWidth: density.temperatureMinimumWidth,
            maxWidth: density.temperatureMaximumWidth,
            alignment: .leading
          )
        cardDivider
      }
      adjustmentValueView(isCondensed: density == .condensed)
        .frame(width: density.temperatureMinimumWidth, alignment: .leading)
        .padding(.trailing, showsControl ? adjustmentControlClearance : 0)
    }
    .frame(maxWidth: .infinity, minHeight: density.minimumHeight)
  }

  private var stackedLayout: some View {
    VStack(alignment: .leading, spacing: 16) {
      location(isCondensed: false)
      cardDivider
      if !reading.isSensorlessZone {
        currentTemperature(isCondensed: false)
        cardDivider
      }
      adjustmentValueView(isCondensed: false)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var cardDivider: some View {
    Divider()
      .overlay(style.dividerColor)
  }

  private func location(isCondensed: Bool) -> some View {
    let iconSize: CGFloat = isCondensed ? 36 : 52

    return HStack(spacing: isCondensed ? 4 : 12) {
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
          .lineLimit(isCondensed ? condensedNameLineLimit : nil)
          .minimumScaleFactor(isCondensed ? 0.75 : 1)

        Text(powerStateLabel)
          .font(.caption)
          .foregroundStyle(style.powerStateForeground)
      }
    }
  }

  private func currentTemperature(isCondensed: Bool) -> some View {
    ClimateCardValue(
      label: copy.current, value: reading.value, unit: reading.unit,
      unavailableLabel: copy.unavailable, foreground: style.primaryForeground,
      secondaryForeground: style.secondaryForeground, isCondensed: isCondensed, fractionLength: 1
    )
  }

  private func adjustmentValueView(isCondensed: Bool) -> some View {
    ClimateCardValue(
      label: reading.isSensorlessZone ? copy.vent : copy.target,
      value: reading.adjustmentValue, unit: reading.adjustmentUnit,
      unavailableLabel: copy.unavailable, foreground: AnyShapeStyle(style.emphasizedForeground),
      secondaryForeground: style.secondaryForeground, isCondensed: isCondensed,
      fractionLength: reading.isSensorlessZone ? 0 : adjustmentFractionLength
    )
  }

}

extension HomeAssistantTemperatureCard {
  fileprivate var condensedNameLineLimit: Int {
    #if os(iOS)
      horizontalSizeClass == .compact ? 1 : 2
    #else
      2
    #endif
  }

  @ViewBuilder
  fileprivate var adjustableCard: some View {
    if dynamicTypeSize.isAccessibilitySize {
      powerCard(usesBottomAdjustmentControlAlignment: true) {
        stackedLayout
      }
    } else {
      #if os(iOS)
        if horizontalSizeClass == .compact {
          powerCard(usesBottomAdjustmentControlAlignment: false) {
            rowLayout(.condensed)
          }
        } else {
          ViewThatFits(in: .horizontal) {
            powerCard(usesBottomAdjustmentControlAlignment: false) {
              rowLayout(.spacious)
            }
            powerCard(usesBottomAdjustmentControlAlignment: false) {
              rowLayout(.condensed)
            }
            powerCard(usesBottomAdjustmentControlAlignment: true) {
              stackedLayout
            }
          }
        }
      #elseif os(macOS)
        if horizontalSizeClass == .compact {
          ViewThatFits(in: .horizontal) {
            powerCard(usesBottomAdjustmentControlAlignment: false) {
              rowLayout(.condensed)
            }
            powerCard(usesBottomAdjustmentControlAlignment: true) {
              stackedLayout
            }
          }
        } else {
          ViewThatFits(in: .horizontal) {
            powerCard(usesBottomAdjustmentControlAlignment: false) {
              rowLayout(.spacious)
            }
            powerCard(usesBottomAdjustmentControlAlignment: false) {
              rowLayout(.condensed)
            }
            powerCard(usesBottomAdjustmentControlAlignment: true) {
              stackedLayout
            }
          }
        }
      #endif
    }
  }

  fileprivate func powerCard<Content: View>(
    usesBottomAdjustmentControlAlignment: Bool,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let adjustmentControlAlignment: Alignment =
      usesBottomAdjustmentControlAlignment ? .bottomTrailing : .trailing
    return Button {
      guard !isAdjustmentControlling else {
        return
      }
      setPower(reading.powerState == .off)
    } label: {
      cardSurface(content: content)
    }
    .buttonStyle(.plain)
    .disabled(!isControlEnabled || isControlling)
    .accessibilityLabel(powerAccessibilityLabel)
    .accessibilityValue(powerAccessibilityValue)
    .allowsHitTesting(!isAdjustmentControlling)
    .focusable(!isAdjustmentControlling)
    .accessibilityRespondsToUserInteraction(!isAdjustmentControlling)
    .overlay(alignment: adjustmentControlAlignment) {
      if showsAdjustmentControl {
        ZoneAdjustmentControl(
          reading: reading,
          mode: mode,
          isEnabled: isControlEnabled,
          isLastKnown: isLastKnown,
          fractionLength: adjustmentFractionLength,
          setAdjustmentValue: setAdjustmentValue
        )
        .padding(
          adjustmentControlInsets(
            usesBottomAdjustmentControlAlignment: usesBottomAdjustmentControlAlignment
          )
        )
      }
    }
  }

  fileprivate func adjustmentControlInsets(
    usesBottomAdjustmentControlAlignment: Bool
  ) -> EdgeInsets {
    #if os(iOS)
      EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8)
    #else
      EdgeInsets(
        top: usesBottomAdjustmentControlAlignment ? 0 : 16,
        leading: 0,
        bottom: 16,
        trailing: 16
      )
    #endif
  }

  fileprivate var adjustmentControlClearance: CGFloat {
    #if os(iOS)
      16
    #else
      36
    #endif
  }

}

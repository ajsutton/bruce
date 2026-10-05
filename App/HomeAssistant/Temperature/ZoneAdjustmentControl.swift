import SwiftUI

struct ZoneAdjustmentControl: View {
  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode
  let isEnabled: Bool
  let isLastKnown: Bool
  let fractionLength: Int
  let setAdjustmentValue: @Sendable (Double) -> Void

  private var style: TemperatureCardStyle {
    TemperatureCardStyle(reading: reading, mode: mode)
  }

  private var copy: TemperatureCopy {
    TemperatureCopy(mode: mode)
  }

  private var isAdjustmentEnabled: Bool {
    guard isEnabled else { return false }
    guard reading.isSensorlessZone else { return true }
    guard let opening = reading.opening, let value = opening.value else { return false }
    return opening.canSetValue(value)
  }

  private var step: Double {
    reading.adjustmentStep
  }

  @ViewBuilder
  var body: some View {
    #if os(iOS)
      ZStack(alignment: .trailing) {
        VStack(spacing: 0) {
          adjustmentSymbol(
            systemName: "chevron.up",
            value: adjustedValue(by: step)
          )
          adjustmentSymbol(
            systemName: "chevron.down",
            value: adjustedValue(by: -step)
          )
        }
        .accessibilityHidden(true)

        VStack(spacing: 0) {
          adjustmentButton(
            accessibilityLabel: reading.isSensorlessZone
              ? copy.increaseVent(name: reading.name) : copy.increaseTarget(name: reading.name),
            value: adjustedValue(by: step)
          )
          adjustmentButton(
            accessibilityLabel: reading.isSensorlessZone
              ? copy.decreaseVent(name: reading.name) : copy.decreaseTarget(name: reading.name),
            value: adjustedValue(by: -step)
          )
        }
      }
      .frame(width: 84, height: 88)
    #else
      Stepper(
        value: valueBinding,
        in: valueRange,
        step: step
      ) {}
      .labelsHidden()
      .disabled(!isAdjustmentEnabled)
      .accessibilityLabel(
        reading.isSensorlessZone
          ? copy.opening(name: reading.name) : copy.target(name: reading.name)
      )
      .accessibilityValue(valueAccessibilityValue)
      .tint(style.controlTint)
      .foregroundStyle(style.primaryForeground)
    #endif
  }

  #if os(iOS)
    private func adjustmentSymbol(
      systemName: String,
      value: Double?
    ) -> some View {
      Image(systemName: systemName)
        .font(.caption.weight(.semibold))
        .foregroundStyle(style.controlTint)
        .frame(width: 16, height: 44)
        .opacity(isAdjustmentEnabled && value != nil ? 1 : 0.35)
    }

    private func adjustmentButton(
      accessibilityLabel: String,
      value: Double?
    ) -> some View {
      Button {
        guard let value else {
          return
        }
        setAdjustmentValue(value)
      } label: {
        Color.clear
          .frame(width: 84, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!isAdjustmentEnabled || value == nil)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityValue(valueAccessibilityValue)
    }

    private func adjustedValue(by adjustment: Double) -> Double? {
      guard let targetValue = reading.adjustmentValue else {
        return nil
      }
      let adjustedValue = targetValue + adjustment
      guard valueRange.contains(adjustedValue) else {
        return nil
      }
      return adjustedValue
    }

  #endif

  private var valueAccessibilityValue: String {
    guard let value = reading.adjustmentValue else {
      return copy.unavailable
    }
    let formattedValue = value.formatted(
      .number.precision(.fractionLength(reading.isSensorlessZone ? 0 : fractionLength))
    )
    let presentedValue = "\(formattedValue)\(reading.adjustmentUnit ?? "")"
    return isLastKnown ? copy.lastKnown(presentedValue) : presentedValue
  }

  private var valueBinding: Binding<Double> {
    Binding(
      get: { reading.adjustmentValue ?? valueRange.lowerBound },
      set: setAdjustmentValue
    )
  }

  private var valueRange: ClosedRange<Double> {
    if reading.isSensorlessZone { return 0...100 }
    let targetValue = reading.adjustmentValue ?? 0
    let lowerBound = reading.minimumTargetValue ?? targetValue - 1_000
    let upperBound = reading.maximumTargetValue ?? targetValue + 1_000
    guard lowerBound <= upperBound else {
      return targetValue...targetValue
    }
    return lowerBound...upperBound
  }
}

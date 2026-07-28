import SwiftUI

struct ZoneTargetTemperatureControl: View {
  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode
  let isEnabled: Bool
  let fractionLength: Int
  let setTargetValue: @Sendable (Double) -> Void

  private var style: TemperatureCardStyle {
    TemperatureCardStyle(reading: reading, mode: mode)
  }

  private var copy: TemperatureCopy {
    TemperatureCopy(mode: mode)
  }

  private var step: Double {
    reading.effectiveTargetValueStep
  }

  @ViewBuilder
  var body: some View {
    #if os(iOS)
      ZStack(alignment: .trailing) {
        VStack(spacing: 0) {
          adjustmentSymbol(
            systemName: "chevron.up",
            value: adjustedTarget(by: step)
          )
          adjustmentSymbol(
            systemName: "chevron.down",
            value: adjustedTarget(by: -step)
          )
        }
        .accessibilityHidden(true)

        VStack(spacing: 0) {
          adjustmentButton(
            accessibilityLabel: copy.increaseTarget(name: reading.name),
            value: adjustedTarget(by: step)
          )
          adjustmentButton(
            accessibilityLabel: copy.decreaseTarget(name: reading.name),
            value: adjustedTarget(by: -step)
          )
        }
      }
      .frame(width: 84, height: 88)
    #else
      Stepper(
        value: targetBinding,
        in: targetRange,
        step: step
      ) {}
      .labelsHidden()
      .disabled(!isEnabled)
      .accessibilityLabel(copy.target(name: reading.name))
      .accessibilityValue(targetAccessibilityValue)
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
        .opacity(isEnabled && value != nil ? 1 : 0.35)
    }

    private func adjustmentButton(
      accessibilityLabel: String,
      value: Double?
    ) -> some View {
      Button {
        guard let value else {
          return
        }
        setTargetValue(value)
      } label: {
        Color.clear
          .frame(width: 84, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!isEnabled || value == nil)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityValue(targetAccessibilityValue)
    }

    private func adjustedTarget(by adjustment: Double) -> Double? {
      guard let targetValue = reading.targetValue else {
        return nil
      }
      let adjustedValue = targetValue + adjustment
      guard targetRange.contains(adjustedValue) else {
        return nil
      }
      return adjustedValue
    }

  #endif

  private var targetAccessibilityValue: Text {
    guard let value = reading.targetValue else {
      return Text(copy.unavailable)
    }
    let formattedValue = value.formatted(
      .number.precision(.fractionLength(fractionLength))
    )
    return Text(verbatim: "\(formattedValue)\(reading.unit ?? "")")
  }

  private var targetBinding: Binding<Double> {
    Binding(
      get: { reading.targetValue ?? targetRange.lowerBound },
      set: setTargetValue
    )
  }

  private var targetRange: ClosedRange<Double> {
    let targetValue = reading.targetValue ?? 0
    let lowerBound = reading.minimumTargetValue ?? targetValue - 1_000
    let upperBound = reading.maximumTargetValue ?? targetValue + 1_000
    guard lowerBound <= upperBound else {
      return targetValue...targetValue
    }
    return lowerBound...upperBound
  }
}

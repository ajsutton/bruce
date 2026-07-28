import SwiftUI

struct ZoneTargetTemperatureControl: View {
  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode
  let isEnabled: Bool
  let showsLabel: Bool
  let fractionLength: Int
  let setTargetValue: @Sendable (Double) -> Void

  private var style: TemperatureCardStyle {
    TemperatureCardStyle(reading: reading, mode: mode)
  }

  private var step: Double {
    reading.effectiveTargetValueStep
  }

  var body: some View {
    if showsLabel {
      stepper
    } else {
      stepper
        .labelsHidden()
    }
  }

  private var stepper: some View {
    Stepper(
      value: targetBinding,
      in: targetRange,
      step: step
    ) {
      VStack(alignment: .trailing, spacing: 2) {
        Text("Target")
          .font(.caption)
          .foregroundStyle(style.secondaryForeground)
        targetValueLabel
          .font(.title3)
          .foregroundStyle(style.emphasizedForeground)
          .monospacedDigit()
      }
    }
    .disabled(!isEnabled)
    .accessibilityLabel("\(reading.name) target")
    .accessibilityValue(targetAccessibilityValue)
    .tint(style.controlTint)
    .foregroundStyle(style.primaryForeground)
  }

  private var targetValueLabel: Text {
    guard let value = reading.targetValue else {
      return Text("—")
    }
    let formattedValue = value.formatted(
      .number.precision(.fractionLength(fractionLength))
    )
    return Text(verbatim: "\(formattedValue)\(reading.unit ?? "")")
  }

  private var targetAccessibilityValue: Text {
    guard let value = reading.targetValue else {
      return Text("Unavailable")
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

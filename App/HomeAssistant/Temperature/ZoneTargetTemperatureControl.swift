import SwiftUI

struct ZoneTargetTemperatureControl: View {
  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode
  let isEnabled: Bool
  let isControlling: Bool
  let fractionLength: Int
  let setTargetValue: @Sendable (Double) -> Void

  private var style: TemperatureCardStyle {
    TemperatureCardStyle(reading: reading, mode: mode)
  }

  private var step: Double {
    reading.effectiveTargetValueStep
  }

  var body: some View {
    Stepper(
      value: targetBinding,
      in: targetRange,
      step: step
    ) {}
    .labelsHidden()
    .disabled(!isEnabled || isControlling)
    .accessibilityLabel("\(reading.name) target")
    .accessibilityValue(targetAccessibilityValue)
    .tint(style.controlTint)
    .foregroundStyle(style.primaryForeground)
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

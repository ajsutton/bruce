import SwiftUI

struct ZoneTargetTemperatureControl: View {
  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode
  let isEnabled: Bool
  let isControlling: Bool
  let setTargetValue: @MainActor @Sendable (Double) -> Void

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
    ) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          targetLabel
          Spacer()
          targetValue
        }
        VStack(alignment: .leading, spacing: 4) {
          targetLabel
          targetValue
        }
      }
    }
    .disabled(!isEnabled || isControlling)
    .accessibilityLabel("\(reading.name) target")
    .accessibilityValue(targetAccessibilityValue)
    .tint(style.controlTint)
    .foregroundStyle(style.primaryForeground)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(style.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(style.cardBorder, lineWidth: 1)
    }
    .shadow(
      color: .black.opacity(mode.isFullBruce ? 0.16 : 0.07),
      radius: 6,
      y: 2
    )
  }

  private var targetLabel: some View {
    Text("Target")
      .font(.subheadline.weight(.semibold))
  }

  private var targetValue: some View {
    HStack(alignment: .firstTextBaseline, spacing: 2) {
      if let value = reading.targetValue {
        Text(
          value,
          format: .number.precision(
            .fractionLength(reading.targetValueFractionLength)
          )
        )
        if let unit = reading.unit {
          Text(unit)
            .font(.body)
        }
      }
    }
    .font(.title3.weight(.semibold))
    .monospacedDigit()
    .accessibilityHidden(true)
  }

  private var targetAccessibilityValue: Text {
    guard let value = reading.targetValue else {
      return Text("Unavailable")
    }
    let formattedValue = value.formatted(
      .number.precision(.fractionLength(reading.targetValueFractionLength))
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

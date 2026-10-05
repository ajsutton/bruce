import SwiftUI

struct SensorlessZoneCard: View {
  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode
  let showsControls: Bool
  let isEnabled: Bool
  let isAdjustingOpening: Bool
  let isControllingPower: Bool
  let isLastKnown: Bool
  let setPower: (Bool) -> Void
  let setOpening: @Sendable (Double) -> Void

  private var copy: TemperatureCopy { TemperatureCopy(mode: mode) }
  private var style: TemperatureCardStyle { TemperatureCardStyle(reading: reading, mode: mode) }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if showsControls {
        Toggle(isOn: Binding(get: { reading.powerState == .poweredOn }, set: setPower)) {
          location
        }
        .toggleStyle(.switch)
        .disabled(!isEnabled || isControllingPower || isAdjustingOpening)
        .accessibilityLabel(reading.name)
        .accessibilityValue(accessibilityValue(powerLabel))
      } else {
        location
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(reading.name)
          .accessibilityValue(accessibilityValue(powerLabel))
      }
      HStack {
        Text(copy.opening).foregroundStyle(style.secondaryForeground)
        Spacer()
        Text(verbatim: openingValue).monospacedDigit()
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(copy.opening(name: reading.name))
      .accessibilityValue(accessibilityValue(openingValue))
      .accessibilityHidden(showsControls && reading.opening?.value != nil)
      if showsControls, let opening = reading.opening, let value = opening.value {
        Stepper(
          value: Binding(get: { value }, set: setOpening), in: 0...100, step: 1
        ) {
          Text(copy.opening)
        }
        .labelsHidden()
        .disabled(!isEnabled || isControllingPower || !opening.canSetValue(value))
        .accessibilityLabel(copy.opening(name: reading.name))
        .accessibilityValue(accessibilityValue(openingValue))
      }
    }
    .foregroundStyle(style.primaryForeground)
    .tint(style.controlTint)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(style.cardBackground, in: RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20).stroke(style.cardBorder, lineWidth: 1)
    }
    .shadow(color: .black.opacity(mode.isFullBruce ? 0.2 : 0.1), radius: 10, y: 4)
  }

  private var location: some View {
    Label {
      VStack(alignment: .leading, spacing: 4) {
        Text(reading.name).font(.headline)
        Text(powerLabel).font(.caption)
      }
    } icon: {
      HomeAssistantTemperatureIconView(identifier: reading.icon)
    }
  }

  private var openingValue: String {
    guard let opening = reading.opening, opening.isAvailable, let value = opening.value else {
      return copy.unavailable
    }
    return "\(value.formatted(.number.precision(.fractionLength(0))))%"
  }

  private func accessibilityValue(_ value: String) -> String {
    isLastKnown ? copy.lastKnown(value) : value
  }

  private var powerLabel: String {
    switch reading.powerState {
    case .poweredOn: copy.powerOn
    case .off: copy.powerOff
    case .unavailable: copy.unavailable
    }
  }
}

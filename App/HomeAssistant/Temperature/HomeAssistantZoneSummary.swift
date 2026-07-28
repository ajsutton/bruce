import SwiftUI

struct HomeAssistantZoneSummary: View {
  let reading: HomeAssistantTemperatureReading
  let mode: BruceMode
  let isControlling: Bool

  private var style: TemperatureCardStyle {
    TemperatureCardStyle(reading: reading, mode: mode)
  }

  var body: some View {
    HStack(spacing: 8) {
      Group {
        if isControlling {
          ProgressView()
            .controlSize(.small)
        } else {
          HomeAssistantTemperatureIconView(identifier: reading.icon)
        }
      }
      .foregroundStyle(style.iconForeground)
      .frame(width: 40, height: 40)
      .background(
        style.iconBackground,
        in: RoundedRectangle(cornerRadius: 12)
      )
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(reading.name)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(style.primaryForeground)
          .lineLimit(1)

        HStack(spacing: 4) {
          Text(
            reading.value,
            format: .number.precision(.fractionLength(1))
          )
          Text(reading.unit ?? "")
          Text(verbatim: "·")
            .accessibilityHidden(true)
          Text(powerStateLabel)
        }
        .font(.caption)
        .foregroundStyle(style.secondaryForeground)
        .monospacedDigit()
      }
    }
    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
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
}

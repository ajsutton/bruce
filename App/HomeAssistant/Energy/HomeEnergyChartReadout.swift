import SwiftUI

struct HomeEnergyChartReadout<Values: View>: View {
  let time: Date
  let freshnessLabel: String?
  @ViewBuilder let values: Values

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Text(time, format: .dateTime.month().day().hour().minute())
        if let freshnessLabel {
          Text(freshnessLabel)
        }
      }
      .foregroundStyle(.secondary)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 14) { values }
        VStack(alignment: .leading, spacing: 4) { values }
      }
    }
    .font(.caption.monospacedDigit())
    .accessibilityElement(children: .combine)
  }
}

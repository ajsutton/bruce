import SwiftUI

struct ClimateCardValue: View {
  let label: String
  let value: Double?
  let unit: String?
  let unavailableLabel: String
  let foreground: AnyShapeStyle
  let secondaryForeground: AnyShapeStyle
  let isCondensed: Bool
  let fractionLength: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(secondaryForeground)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        if let value {
          Text(value, format: .number.precision(.fractionLength(fractionLength)))
          if let unit {
            Text(unit).font(isCondensed ? .body : .title2)
          }
        } else {
          Text(verbatim: "—").accessibilityLabel(unavailableLabel)
        }
      }
      .font(.system(isCondensed ? .title2 : .largeTitle, design: .rounded, weight: .medium))
      .foregroundStyle(foreground)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.5)
    }
  }
}

import SwiftUI

extension EnergyWidgetView {
  var unavailableContent: some View {
    VStack(spacing: 8) {
      Spacer()
      Image(systemName: "bolt.slash")
        .font(.title2)
        .foregroundStyle(palette.secondary)
        .accessibilityHidden(true)
      Text(copy.energyUnavailable)
        .font(.caption)
        .multilineTextAlignment(.center)
        .foregroundStyle(palette.secondary)
      Text(copy.openBruceDetails)
        .font(.caption2)
        .multilineTextAlignment(.center)
        .foregroundStyle(palette.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  func freshnessLabel(compact: Bool) -> some View {
    HStack(spacing: 3) {
      if freshnessMinutes == 0 {
        Image(systemName: "checkmark.circle")
          .accessibilityHidden(true)
        Text(copy.upToDate)
      } else if hasLastKnownValues {
        Image(systemName: entry.freshness == .lastKnown ? "clock" : "clock.arrow.circlepath")
          .accessibilityHidden(true)
        Text(copy.lastKnown)
        if !compact {
          Text("·")
            .accessibilityHidden(true)
          freshnessAge
        }
      } else {
        Image(systemName: "clock")
          .accessibilityHidden(true)
        Text(copy.updated)
        freshnessAge
      }
    }
    .font(.caption2)
    .foregroundStyle(palette.secondary)
    .lineLimit(1)
    .fixedSize(horizontal: false, vertical: true)
    .layoutPriority(1)
    .accessibilityElement(children: .combine)
  }

  private var freshnessAge: Text {
    guard let freshnessCaptureDate else { return Text("") }
    return Text(
      .now,
      format: .reference(
        to: freshnessCaptureDate,
        allowedFields: [.minute],
        maxFieldCount: 1,
        thresholdField: .minute
      )
    )
  }

  func accessoryMetric(_ metric: EnergyWidgetMetric) -> some View {
    HStack(spacing: 2) {
      Text("\(metric.title): \(metric.value)")
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(metric.accessibilityLabel)
    .accessibilityValue(accessibilityValue(for: metric))
  }

  func accessibilityValue(for metric: EnergyWidgetMetric) -> String {
    if entry.freshness == .lastKnown || metric.isLastKnown {
      return "\(copy.lastKnown): \(metric.value)"
    }
    return metric.value
  }

  private var hasLastKnownValues: Bool {
    guard let snapshot = entry.snapshot else { return false }
    return entry.freshness == .lastKnown
      || !snapshot.readingsAreCurrent
      || !snapshot.importCostIsCurrent
      || !snapshot.feedInEarningsIsCurrent
  }

  private var freshnessCaptureDate: Date? {
    guard let snapshot = entry.snapshot else { return nil }
    return hasLastKnownValues
      ? snapshot.oldestLastKnownCapture ?? snapshot.capturedAt
      : snapshot.capturedAt
  }

  private var freshnessMinutes: Int {
    guard let freshnessCaptureDate else { return 0 }
    return EnergyWidgetFreshnessSchedule.wholeMinutes(
      from: freshnessCaptureDate,
      to: entry.date
    )
  }
}

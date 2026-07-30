import Charts
import SwiftUI

struct HomeAssistantHomeEnergyBatteryChart: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject var store: HomeEnergyBatteryHistoryStore
  let mode: BruceMode

  private var copy: HomeEnergyCopy {
    HomeEnergyCopy(mode: mode)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      chartHeader

      if store.hasUsableHistory {
        batteryChart
        if store.problem != nil {
          Label(
            copy.batteryHistoryLoadFailed,
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(secondaryForeground)
        }
      } else if store.showsProgress {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 220)
          .accessibilityLabel(copy.batteryHistoryLoading)
      } else if store.problem != nil {
        ContentUnavailableView(
          copy.batteryHistoryLoadFailed,
          systemImage: "exclamationmark.triangle"
        )
        .frame(maxWidth: .infinity, minHeight: 220)
      } else if store.isUnavailable || !store.isLoading {
        ContentUnavailableView(
          copy.batteryHistoryUnavailable,
          systemImage: "battery.50percent"
        )
        .frame(maxWidth: .infinity, minHeight: 220)
      } else {
        Color.clear
          .frame(maxWidth: .infinity, minHeight: 220)
          .accessibilityLabel(copy.batteryHistoryLoading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(borderColor, lineWidth: 1)
    }
    .shadow(
      color: .black.opacity(mode.isFullBruce ? 0.2 : 0.1),
      radius: 10,
      y: 4
    )
  }

  private var chartHeader: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(copy.batteryHistory)
        .font(.headline)
        .foregroundStyle(primaryForeground)
      HStack(spacing: 4) {
        Text(copy.batteryHistoryPeriod)
        if let freshnessLabel {
          Text("·")
            .accessibilityHidden(true)
          Text(freshnessLabel)
        }
      }
      .font(.caption)
      .foregroundStyle(secondaryForeground)
    }
  }

  private var batteryChart: some View {
    Chart {
      ForEach(
        Array(store.batteryHistory.availableReadingSegments.enumerated()),
        id: \.offset
      ) { segmentIndex, segment in
        ForEach(segment) { reading in
          if let stateOfCharge = reading.stateOfCharge {
            LineMark(
              x: .value(copy.batteryHistoryTimeAxis, reading.timestamp),
              y: .value(copy.batteryHistoryChargeAxis, stateOfCharge),
              series: .value(copy.batteryHistorySeries, segmentIndex)
            )
            .foregroundStyle(mode.accentColor)
            .interpolationMethod(.stepEnd)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
          }
        }
      }
    }
    .chartXScale(
      domain: store.batteryHistory.interval.start...store.batteryHistory.interval.end
    )
    .chartYScale(domain: 0...100)
    .chartXAxis {
      AxisMarks(values: .stride(by: .hour, count: 6)) {
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: .dateTime.hour())
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel {
          if let percentage = value.as(Int.self) {
            Text("\(percentage)%")
          }
        }
      }
    }
    .frame(minHeight: 220)
    .accessibilityChartDescriptor(batteryAccessibilityDescriptor)
  }

  private var freshnessLabel: String? {
    if store.isLoading, store.hasUsableHistory {
      return copy.updatingLastKnownStatus
    }
    if store.isStale, store.hasUsableHistory {
      return copy.lastKnown
    }
    return nil
  }

  var batteryAccessibilityDescriptor: HomeEnergyChartAccessibilityDescriptor {
    HomeEnergyChartAccessibilityDescriptor(
      title: copy.batteryHistory,
      summary: accessibilitySummary,
      timeAxisTitle: copy.batteryHistoryTimeAxis,
      valueAxisTitle: copy.batteryHistoryChargeAxis,
      interval: store.batteryHistory.interval,
      valueRange: 0...100,
      valueDescription: {
        "\($0.formatted(.number.precision(.fractionLength(0...1))))%"
      },
      series: store.batteryHistory.availableReadingSegments.map { segment in
        .init(
          name: copy.batteryHistory,
          points: segment.compactMap { reading in
            reading.stateOfCharge.map { (reading.timestamp, $0) }
          }
        )
      }
    )
  }

  private var accessibilitySummary: String {
    guard let freshnessLabel else { return copy.batteryHistoryPeriod }
    return "\(copy.batteryHistoryPeriod). \(freshnessLabel)."
  }

  private var primaryForeground: AnyShapeStyle {
    mode.isFullBruce ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
  }

  private var secondaryForeground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color.white.opacity(0.76))
      : AnyShapeStyle(.secondary)
  }

  private var cardBackground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color(red: 0.00, green: 0.25, blue: 0.18))
      : AnyShapeStyle(.background)
  }

  private var borderColor: Color {
    if mode.isFullBruce {
      return mode.accentColor.opacity(0.28)
    }
    return colorScheme == .dark
      ? Color.white.opacity(0.08)
      : mode.foregroundColor.opacity(0.08)
  }
}

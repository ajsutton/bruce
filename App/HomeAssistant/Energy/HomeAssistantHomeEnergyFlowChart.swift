import Charts
import SwiftUI

struct HomeAssistantHomeEnergyFlowChart: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject var store: HomeEnergyFlowHistoryStore
  let mode: BruceMode

  var copy: HomeEnergyCopy {
    HomeEnergyCopy(mode: mode)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      chartHeader

      if store.hasUsableHistory {
        flowChart
        if store.problem != nil {
          Label(
            copy.flowHistoryLoadFailed,
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(secondaryForeground)
        }
      } else if store.showsProgress {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 220)
          .accessibilityLabel(copy.flowHistoryLoading)
      } else if store.problem != nil {
        ContentUnavailableView(
          copy.flowHistoryLoadFailed,
          systemImage: "exclamationmark.triangle"
        )
        .frame(maxWidth: .infinity, minHeight: 220)
      } else if store.isUnavailable || !store.isLoading {
        ContentUnavailableView(
          copy.flowHistoryUnavailable,
          systemImage: "chart.xyaxis.line"
        )
        .frame(maxWidth: .infinity, minHeight: 220)
      } else {
        Color.clear
          .frame(maxWidth: .infinity, minHeight: 220)
          .accessibilityLabel(copy.flowHistoryLoading)
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

  var flowYDomain: ClosedRange<Double> {
    let maximumMagnitude =
      store.flowHistory.readings
      .compactMap(\.kilowatts)
      .map(abs)
      .max() ?? 0
    let bound = max((maximumMagnitude * 1.08).rounded(.up), 1)
    return -bound...bound
  }

  func seriesName(for series: HomeEnergyFlowHistory.Series) -> String {
    switch series {
    case .pvGeneration:
      copy.flowPVGeneration
    case .homeUsage:
      copy.flowHomeUsage
    case .grid:
      copy.flowGrid
    case .battery:
      copy.flowBattery
    }
  }

  var freshnessLabel: String? {
    if store.isLoading, store.hasUsableHistory {
      return copy.updatingLastKnownStatus
    }
    if store.isStale, store.hasUsableHistory {
      return copy.lastKnown
    }
    return nil
  }
}

extension HomeAssistantHomeEnergyFlowChart {
  private var chartHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(copy.flowHistory)
          .font(.headline)
          .foregroundStyle(primaryForeground)
        HStack(spacing: 4) {
          Text(copy.flowHistoryPeriod)
          if let freshnessLabel {
            Text("·")
              .accessibilityHidden(true)
            Text(freshnessLabel)
          }
        }
        Text(copy.flowHistoryPolarity)
          .fixedSize(horizontal: false, vertical: true)
      }
      .font(.caption)
      .foregroundStyle(secondaryForeground)

      if store.hasUsableHistory {
        chartLegend
      }
    }
  }

  private var chartLegend: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        ForEach(HomeEnergyFlowHistory.Series.allCases, id: \.self) {
          legendItem(for: $0)
        }
      }

      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
        GridRow {
          legendItem(for: .pvGeneration)
          legendItem(for: .homeUsage)
        }
        GridRow {
          legendItem(for: .grid)
          legendItem(for: .battery)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        ForEach(HomeEnergyFlowHistory.Series.allCases, id: \.self) {
          legendItem(for: $0)
        }
      }
    }
    .font(.caption)
    .foregroundStyle(secondaryForeground)
    .accessibilityElement(children: .contain)
  }

  private func legendItem(
    for series: HomeEnergyFlowHistory.Series
  ) -> some View {
    HStack(spacing: 5) {
      Path { path in
        path.move(to: CGPoint(x: 0, y: 2))
        path.addLine(to: CGPoint(x: 18, y: 2))
      }
      .stroke(
        color(for: series),
        style: StrokeStyle(lineWidth: 1)
      )
      .frame(width: 18, height: 4)
      .accessibilityHidden(true)
      Text(seriesName(for: series))
    }
  }

  private var flowChart: some View {
    Chart {
      RuleMark(y: .value(copy.flowHistoryPowerAxis, 0))
        .foregroundStyle(secondaryRuleColor)
        .lineStyle(StrokeStyle(lineWidth: 1))

      ForEach(HomeEnergyFlowHistory.Series.allCases, id: \.self) { series in
        ForEach(
          Array(
            (store.flowHistory.availableReadingSegments[series] ?? [])
              .enumerated()
          ),
          id: \.offset
        ) { segmentIndex, segment in
          ForEach(segment) { reading in
            flowLine(
              reading,
              series: series,
              segmentIndex: segmentIndex
            )
          }
        }
      }
    }
    .chartXScale(domain: store.flowHistory.interval.start...store.flowHistory.interval.end)
    .chartYScale(domain: flowYDomain)
    .chartForegroundStyleScale(
      domain: HomeEnergyFlowHistory.Series.allCases.map(seriesName),
      range: HomeEnergyFlowHistory.Series.allCases.map(color)
    )
    .chartLegend(.hidden)
    .chartXAxis {
      AxisMarks(values: .stride(by: .hour, count: 6)) {
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: .dateTime.hour())
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel {
          if let kilowatts = value.as(Double.self) {
            Text(
              "\(kilowatts.formatted(.number.precision(.fractionLength(0...1)))) kW"
            )
          }
        }
      }
    }
    .frame(minHeight: 220)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .accessibilityChartDescriptor(flowAccessibilityDescriptor)
  }

  @ChartContentBuilder
  private func flowLine(
    _ reading: HomeEnergyFlowHistory.Reading,
    series: HomeEnergyFlowHistory.Series,
    segmentIndex: Int
  ) -> some ChartContent {
    if let kilowatts = reading.kilowatts {
      let seriesID = "\(series.rawValue)-\(segmentIndex)"
      LineMark(
        x: .value(copy.flowHistoryTimeAxis, reading.timestamp),
        y: .value(copy.flowHistoryPowerAxis, kilowatts),
        series: .value(copy.flowHistorySeries, seriesID)
      )
      .foregroundStyle(
        by: .value(copy.flowHistorySeries, seriesName(for: series))
      )
      .interpolationMethod(.linear)
      .lineStyle(StrokeStyle(lineWidth: 1))
    }
  }

  private func color(for series: HomeEnergyFlowHistory.Series) -> Color {
    switch series {
    case .pvGeneration:
      .orange
    case .homeUsage:
      .blue
    case .grid:
      .green
    case .battery:
      .purple
    }
  }

  private var primaryForeground: AnyShapeStyle {
    mode.isFullBruce ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
  }

  private var secondaryForeground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color.white.opacity(0.76))
      : AnyShapeStyle(.secondary)
  }

  private var secondaryRuleColor: Color {
    mode.isFullBruce ? Color.white.opacity(0.45) : Color.secondary.opacity(0.55)
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

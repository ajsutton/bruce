import Charts
import SwiftUI

struct HomeAssistantHomeEnergyPriceChart: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject var store: HomeEnergyPriceHistoryStore
  let mode: BruceMode

  private var copy: HomeEnergyCopy {
    HomeEnergyCopy(mode: mode)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      chartHeader

      if store.hasUsableHistory {
        priceChart
      } else if store.showsProgress {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 220)
          .accessibilityLabel(copy.priceHistoryLoading)
      } else if store.isUnavailable || !store.isLoading {
        ContentUnavailableView(
          copy.priceHistoryUnavailable,
          systemImage: "chart.xyaxis.line"
        )
        .frame(maxWidth: .infinity, minHeight: 220)
      } else {
        Color.clear
          .frame(maxWidth: .infinity, minHeight: 220)
          .accessibilityLabel(copy.priceHistoryLoading)
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
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 16) {
        chartTitle
        Spacer(minLength: 0)
        if store.hasUsableHistory {
          chartLegend
            .fixedSize(horizontal: true, vertical: false)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        chartTitle
        if store.hasUsableHistory {
          chartLegend
        }
      }
    }
  }

  private var chartTitle: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(copy.priceHistory)
        .font(.headline)
        .foregroundStyle(primaryForeground)
      HStack(spacing: 4) {
        Text(copy.priceHistoryPeriod)
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

  private var chartLegend: some View {
    HStack(spacing: 12) {
      legendItem(copy.generalPrice, tariff: .general, color: .orange)
      legendItem(copy.feedInPrice, tariff: .feedIn, color: .green)
    }
    .font(.caption)
    .foregroundStyle(secondaryForeground)
    .accessibilityElement(children: .contain)
  }

  private func legendItem(
    _ title: String,
    tariff: HomeEnergyPriceHistory.Tariff,
    color: Color
  ) -> some View {
    HStack(spacing: 5) {
      Path { path in
        path.move(to: CGPoint(x: 0, y: 2))
        path.addLine(to: CGPoint(x: 18, y: 2))
      }
      .stroke(color, style: lineStyle(for: tariff, width: 2.5))
      .frame(width: 18, height: 4)
      .accessibilityHidden(true)
      Text(title)
    }
  }

  private var priceChart: some View {
    Chart(store.priceHistory.readingsExtendingToIntervalEnd) { reading in
      LineMark(
        x: .value(copy.priceHistoryTimeAxis, reading.timestamp),
        y: .value(
          copy.priceHistoryPriceAxis,
          reading.centsPerKilowattHour
        ),
        series: .value(copy.priceHistorySeries, seriesName(for: reading.tariff))
      )
      .foregroundStyle(
        by: .value(
          copy.priceHistorySeries,
          seriesName(for: reading.tariff)
        )
      )
      .interpolationMethod(.stepEnd)
      .lineStyle(lineStyle(for: reading.tariff, width: 2.5))
    }
    .chartXScale(domain: store.priceHistory.interval.start...store.priceHistory.interval.end)
    .chartYScale(domain: priceYDomain)
    .chartForegroundStyleScale(
      domain: [copy.generalPrice, copy.feedInPrice],
      range: [Color.orange, Color.green]
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
          if let cents = value.as(Double.self) {
            Text(
              "\(cents.formatted(.number.precision(.fractionLength(0...1))))¢"
            )
          }
        }
      }
    }
    .frame(minHeight: 220)
  }

  private var priceYDomain: ClosedRange<Double> {
    let values = store.priceHistory.readingsExtendingToIntervalEnd.map(
      \.centsPerKilowattHour
    )
    guard
      let minimum = values.min(),
      let maximum = values.max()
    else {
      return 0...1
    }
    let padding = max((maximum - minimum) * 0.08, 1)
    let lowerBound = (minimum - padding).rounded(.down)
    let upperBound = (maximum + padding).rounded(.up)
    return lowerBound...upperBound
  }

  private func seriesName(
    for tariff: HomeEnergyPriceHistory.Tariff
  ) -> String {
    switch tariff {
    case .general:
      copy.generalPrice
    case .feedIn:
      copy.feedInPrice
    }
  }

  private func lineStyle(
    for tariff: HomeEnergyPriceHistory.Tariff,
    width: Double
  ) -> StrokeStyle {
    switch tariff {
    case .general:
      StrokeStyle(lineWidth: width)
    case .feedIn:
      StrokeStyle(lineWidth: width, dash: [6, 4])
    }
  }

  private var freshnessLabel: String? {
    if store.isLoading, store.hasUsableHistory {
      return copy.updating
    }
    if store.isStale, store.hasUsableHistory {
      return copy.lastKnown
    }
    return nil
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

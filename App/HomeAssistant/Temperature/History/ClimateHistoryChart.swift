import Charts
import SwiftUI

struct ClimateHistoryChart: View, Equatable {
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let zone: ClimateHistoryZone
  let points: [ClimateHistoryPoint]
  let interval: DateInterval
  let unit: String
  let mode: BruceMode
  let isStale: Bool
  var height: CGFloat = 190
  @State private var selectedTime: Date?

  private var copy: ClimateHistoryCopy { ClimateHistoryCopy(mode: mode) }
  private var chartData: ClimateHistoryChartData { ClimateHistoryChartData(points: points) }
  private var selectedPoint: ClimateHistoryPoint? {
    guard let selectedTime else { return points.last }
    return points.last(where: { $0.timestamp <= selectedTime })
  }

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.zone == rhs.zone && lhs.points == rhs.points && lhs.interval == rhs.interval
      && lhs.unit == rhs.unit && lhs.mode == rhs.mode && lhs.isStale == rhs.isStale
      && lhs.height == rhs.height
  }

  var body: some View {
    let data = chartData
    VStack(alignment: .leading, spacing: 10) {
      readout
      chart(data)
      legend
    }
    .onChange(of: interval) { _, interval in
      if let selectedTime, !interval.contains(selectedTime) { self.selectedTime = nil }
    }
  }

  private var readout: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        if let selectedTime {
          Text(selectedTime, format: .dateTime.hour().minute())
        }
        if isStale {
          Text(copy.lastKnown)
        }
        Spacer()
        Text(copy.activity(selectedPoint?.value.activity ?? .unknown))
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 14) { selectedValues }
        VStack(alignment: .leading, spacing: 4) { selectedValues }
      }
      .font(.caption.monospacedDigit())
    }
  }

  @ViewBuilder private var selectedValues: some View {
    Text("\(copy.actual) \(formatted(selectedPoint?.value.actual, unit: unit))")
    Text("\(copy.target) \(formatted(selectedPoint?.value.target, unit: unit))")
    Text("\(copy.opening) \(formatted(selectedPoint?.value.opening, unit: "%"))")
  }

  private func chart(_ data: ClimateHistoryChartData) -> some View {
    Chart { marks(data) }
      .chartXScale(domain: interval.start...interval.end)
      .chartYScale(domain: data.temperatureRange)
      .chartXSelection(value: $selectedTime)
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 2 : 4)) {
          AxisGridLine()
          AxisValueLabel(format: .dateTime.hour().minute(), collisionResolution: .greedy)
        }
      }
      .chartYAxis { valueAxes(data) }
      .chartYAxisLabel(unit, position: .trailing)
      .frame(height: height)
      .accessibilityChartDescriptor(
        ClimateHistoryAccessibilityDescriptor(
          title: zone.name, copy: copy, data: data, interval: interval, unit: unit, isStale: isStale
        )
      )
  }

  @ChartContentBuilder
  private func marks(_ data: ClimateHistoryChartData) -> some ChartContent {
    ForEach(data.bands) { band in
      RectangleMark(xStart: .value(copy.time, band.start), xEnd: .value(copy.time, band.end))
        .foregroundStyle(Color.blue.opacity(contrast == .increased ? 0.25 : 0.10))
        .accessibilityHidden(true)
      RuleMark(x: .value(copy.time, band.start))
        .foregroundStyle(.secondary.opacity(contrast == .increased ? 1 : 0.4))
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
        .accessibilityHidden(true)
      RuleMark(x: .value(copy.time, band.end))
        .foregroundStyle(.secondary.opacity(contrast == .increased ? 1 : 0.4))
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
        .accessibilityHidden(true)
    }
    traces(data)
    if let selectedTime {
      RuleMark(x: .value(copy.time, selectedTime))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
  }

  @ChartContentBuilder
  private func traces(_ data: ClimateHistoryChartData) -> some ChartContent {
    ForEach(data.traces) { trace in
      ForEach(trace.points) { point in
        if trace.points.count == 1 {
          PointMark(
            x: .value(copy.time, point.timestamp),
            y: .value(
              label(trace.series), chartValue(point.value, series: trace.series, data: data))
          )
          .foregroundStyle(color(trace.series))
        }
        LineMark(
          x: .value(copy.time, point.timestamp),
          y: .value(
            label(trace.series), chartValue(point.value, series: trace.series, data: data)),
          series: .value(copy.title, trace.id)
        )
        .foregroundStyle(color(trace.series))
        .interpolationMethod(.stepEnd)
        .lineStyle(
          StrokeStyle(
            lineWidth: trace.series == .opening ? 1 : 2,
            dash: dash(trace.series)))
      }
    }
  }

  @AxisContentBuilder
  private func valueAxes(_ data: ClimateHistoryChartData) -> some AxisContent {
    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
      AxisGridLine()
      AxisValueLabel()
    }
    AxisMarks(
      position: .leading,
      values: [data.temperatureRange.lowerBound, data.temperatureRange.upperBound]
    ) { value in
      AxisValueLabel {
        if let number = value.as(Double.self) {
          Text(verbatim: number == data.temperatureRange.lowerBound ? "0%" : "100%")
        }
      }
    }
  }

  private var legend: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 16) { legendItems }
      VStack(alignment: .leading, spacing: 6) { legendItems }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  @ViewBuilder private var legendItems: some View {
    ForEach(ClimateHistoryChartData.Series.allCases, id: \.self) { series in
      HStack(spacing: 5) {
        UnevenRoundedRectangle(
          cornerRadii: .init(topLeading: 1, bottomLeading: 1, bottomTrailing: 1, topTrailing: 1)
        )
        .stroke(
          color(series), style: StrokeStyle(lineWidth: 2, dash: dash(series))
        )
        .frame(width: 18, height: 1)
        Text(label(series))
      }
      .accessibilityElement(children: .combine)
    }
    HStack(spacing: 5) {
      Rectangle().fill(Color.blue.opacity(contrast == .increased ? 0.25 : 0.10))
        .overlay { Rectangle().stroke(.secondary, lineWidth: 1) }
        .frame(width: 14, height: 10)
      Text(copy.activity(.active))
    }
    .accessibilityElement(children: .combine)
  }

  private func chartValue(
    _ value: Double, series: ClimateHistoryChartData.Series, data: ClimateHistoryChartData
  ) -> Double {
    guard series == .opening else { return value }
    return data.temperatureRange.lowerBound + value / 100
      * (data.temperatureRange.upperBound - data.temperatureRange.lowerBound)
  }

  private func dash(_ series: ClimateHistoryChartData.Series) -> [CGFloat] {
    switch series {
    case .actual: []
    case .target: [6, 4]
    case .opening: [2, 3]
    }
  }

  private func color(_ series: ClimateHistoryChartData.Series) -> Color {
    switch series {
    case .actual: Color(red: 0.13, green: 0.50, blue: 0.24)
    case .target: .blue
    case .opening: Color(red: 0.78, green: 0.40, blue: 0.08)
    }
  }

  private func label(_ series: ClimateHistoryChartData.Series) -> String {
    switch series {
    case .actual: copy.actual
    case .target: copy.target
    case .opening: copy.opening
    }
  }

  private func formatted(_ value: Double?, unit: String) -> String {
    guard let value else { return "—" }
    return value.formatted(.number.precision(.fractionLength(unit == "%" ? 0 : 1))) + unit
  }
}

import Accessibility
import SwiftUI

struct ClimateHistoryAccessibilityDescriptor: AXChartDescriptorRepresentable {
  let title: String
  let copy: ClimateHistoryCopy
  let data: ClimateHistoryChartData
  let interval: DateInterval
  let unit: String
  let isStale: Bool

  func makeChartDescriptor() -> AXChartDescriptor {
    let time = AXNumericDataAxisDescriptor(
      title: copy.time,
      range: interval.start
        .timeIntervalSinceReferenceDate...interval.end.timeIntervalSinceReferenceDate,
      gridlinePositions: []
    ) { Date(timeIntervalSinceReferenceDate: $0).formatted(.dateTime.hour().minute()) }
    let temperature = AXNumericDataAxisDescriptor(
      title: copy.temperature, range: data.temperatureRange, gridlinePositions: []
    ) { $0.formatted(.number.precision(.fractionLength(1))) + unit }
    let opening = AXNumericDataAxisDescriptor(
      title: copy.opening, range: 0...100, gridlinePositions: []
    ) { $0.formatted(.number.precision(.fractionLength(0))) + "%" }
    let series = data.traces.map { trace in
      AXDataSeriesDescriptor(
        name: label(trace.series), isContinuous: true,
        dataPoints: trace.points.map { point in
          if trace.series == .opening {
            AXDataPoint(
              x: point.timestamp.timeIntervalSinceReferenceDate, y: nil,
              additionalValues: [.number(point.value)])
          } else {
            AXDataPoint(x: point.timestamp.timeIntervalSinceReferenceDate, y: point.value)
          }
        }
      )
    }
    return AXChartDescriptor(
      title: title, summary: activitySummary,
      xAxis: time, yAxis: temperature, additionalAxes: [opening], series: series
    )
  }

  private var activitySummary: String {
    let intervals = data.activityIntervals.map {
      "\(copy.activity($0.activity)): \($0.start.formatted(.dateTime.hour().minute()))–\($0.end.formatted(.dateTime.hour().minute()))"
    }.joined(separator: ". ")
    return isStale ? "\(copy.lastKnown). \(intervals)" : intervals
  }

  private func label(_ series: ClimateHistoryChartData.Series) -> String {
    switch series {
    case .actual: copy.actual
    case .target: copy.target
    case .opening: copy.opening
    }
  }
}

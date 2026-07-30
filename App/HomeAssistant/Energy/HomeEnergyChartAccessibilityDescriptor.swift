import Accessibility
import SwiftUI

struct HomeEnergyChartAccessibilityDescriptor: AXChartDescriptorRepresentable {
  struct Series {
    let name: String
    let points: [(timestamp: Date, value: Double)]
  }

  let title: String
  let summary: String
  let timeAxisTitle: String
  let valueAxisTitle: String
  let interval: DateInterval
  let valueRange: ClosedRange<Double>
  let valueDescription: (Double) -> String
  let series: [Series]

  func makeChartDescriptor() -> AXChartDescriptor {
    let timeRange = ClosedRange(
      uncheckedBounds: (
        lower: interval.start.timeIntervalSinceReferenceDate,
        upper: interval.end.timeIntervalSinceReferenceDate
      )
    )
    let xAxis = AXNumericDataAxisDescriptor(
      title: timeAxisTitle,
      range: timeRange,
      gridlinePositions: []
    ) { value in
      Date(timeIntervalSinceReferenceDate: value).formatted(
        .dateTime.weekday().hour().minute()
      )
    }
    let yAxis = AXNumericDataAxisDescriptor(
      title: valueAxisTitle,
      range: valueRange,
      gridlinePositions: []
    ) { value in
      valueDescription(value)
    }
    let dataSeries = series.map { series in
      AXDataSeriesDescriptor(
        name: series.name,
        isContinuous: true,
        dataPoints: series.points.map {
          AXDataPoint(
            x: $0.timestamp.timeIntervalSinceReferenceDate,
            y: $0.value
          )
        }
      )
    }
    return AXChartDescriptor(
      title: title,
      summary: summary,
      xAxis: xAxis,
      yAxis: yAxis,
      series: dataSeries
    )
  }
}

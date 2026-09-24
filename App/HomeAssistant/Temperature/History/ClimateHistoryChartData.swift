import Foundation

struct ClimateHistoryChartData: Equatable {
  enum Series: String, CaseIterable {
    case actual, target, opening

    func value(in point: ClimateHistoryPoint) -> Double? {
      switch self {
      case .actual: point.value.actual
      case .target: point.value.target
      case .opening: point.value.opening
      }
    }
  }

  struct Trace: Equatable, Identifiable {
    let id: String
    let series: Series
    let points: [ChartPoint]
  }

  struct ChartPoint: Equatable, Identifiable {
    let timestamp: Date
    let value: Double
    var id: Date { timestamp }
  }

  struct Band: Equatable, Identifiable {
    let start: Date
    let end: Date
    var id: Date { start }
  }

  struct ActivityInterval: Equatable {
    let start: Date
    let end: Date
    let activity: ClimateHistoryValue.Activity
  }

  let activityIntervals: [ActivityInterval]
  let traces: [Trace]
  let bands: [Band]
  let temperatureRange: ClosedRange<Double>

  init(points: [ClimateHistoryPoint]) {
    traces = Series.allCases.flatMap { Self.traces(for: $0, points: points) }
    activityIntervals = Self.activityIntervals(points)
    bands = activityIntervals.compactMap {
      $0.activity == .active ? Band(start: $0.start, end: $0.end) : nil
    }
    let temperatures = points.flatMap { [$0.value.actual, $0.value.target].compactMap { $0 } }
    temperatureRange =
      floor(min(temperatures.min() ?? 18, 18))...ceil(max(temperatures.max() ?? 26, 26))
  }

  private static func activityIntervals(_ points: [ClimateHistoryPoint]) -> [ActivityInterval] {
    var result: [ActivityInterval] = []
    for (start, end) in zip(points, points.dropFirst()) {
      if let last = result.last, last.activity == start.value.activity {
        result[result.count - 1] = ActivityInterval(
          start: last.start, end: end.timestamp, activity: last.activity)
      } else {
        result.append(
          ActivityInterval(
            start: start.timestamp, end: end.timestamp, activity: start.value.activity))
      }
    }
    return result
  }

  private static func traces(for series: Series, points: [ClimateHistoryPoint]) -> [Trace] {
    var result: [Trace] = []
    var segment: [ChartPoint] = []
    for point in points {
      if let value = series.value(in: point) {
        segment.append(ChartPoint(timestamp: point.timestamp, value: value))
      } else if let last = segment.last {
        // Extend a known step to the start of its gap, then break the line.
        segment.append(ChartPoint(timestamp: point.timestamp, value: last.value))
        result.append(
          Trace(id: "\(series.rawValue)-\(result.count)", series: series, points: segment))
        segment = []
      }
    }
    if !segment.isEmpty {
      result.append(
        Trace(id: "\(series.rawValue)-\(result.count)", series: series, points: segment))
    }
    return result
  }
}

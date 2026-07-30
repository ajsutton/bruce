import Foundation

struct HomeEnergyFlowHistory: Equatable, Sendable {
  enum Series: String, CaseIterable, Equatable, Hashable, Sendable {
    case pvGeneration
    case homeUsage
    case grid
    case battery

    func value(from snapshot: HomeAssistantHomeEnergySnapshot) -> Double? {
      switch self {
      case .pvGeneration:
        snapshot.pvPowerKilowatts
      case .homeUsage:
        snapshot.homeConsumptionKilowatts
      case .grid:
        snapshot.gridPowerKilowatts
      case .battery:
        snapshot.batteryPowerKilowatts
      }
    }
  }

  struct ReadingIdentifier: Hashable, Sendable {
    let series: Series
    let timestamp: Date
  }

  struct Reading: Equatable, Identifiable, Sendable {
    let series: Series
    let timestamp: Date
    let kilowatts: Double?

    var id: ReadingIdentifier {
      ReadingIdentifier(series: series, timestamp: timestamp)
    }
  }

  static let empty = HomeEnergyFlowHistory(
    interval: DateInterval(start: .distantPast, duration: 0),
    readings: []
  )

  let interval: DateInterval
  let readings: [Reading]

  var hasCompleteSeries: Bool {
    Set(readings.compactMap { $0.kilowatts == nil ? nil : $0.series })
      == Set(Series.allCases)
  }

  var availableReadingSegments: [Series: [[Reading]]] {
    var segmentsBySeries: [Series: [[Reading]]] = [:]
    for series in Series.allCases {
      var segments: [[Reading]] = []
      var currentSegment: [Reading] = []
      for reading in readings where reading.series == series {
        if reading.kilowatts != nil {
          currentSegment.append(reading)
        } else if !currentSegment.isEmpty {
          extend(&currentSegment, to: reading.timestamp)
          segments.append(currentSegment)
          currentSegment = []
        }
      }
      if !currentSegment.isEmpty {
        extend(&currentSegment, to: interval.end)
        segments.append(currentSegment)
      }
      segmentsBySeries[series] = segments
    }
    return segmentsBySeries
  }

  func recording(
    snapshot: HomeAssistantHomeEnergySnapshot,
    at timestamp: Date
  ) -> HomeEnergyFlowHistory {
    let start = timestamp.addingTimeInterval(-24 * 60 * 60)
    var updatedReadings = readingsPreservingValues(at: start)
    for series in Series.allCases {
      append(
        series.value(from: snapshot),
        series: series,
        at: timestamp,
        to: &updatedReadings
      )
    }
    return HomeEnergyFlowHistory(
      interval: DateInterval(start: start, end: timestamp),
      readings: sorted(updatedReadings)
    )
  }

  func mergingLiveReadings(
    from liveHistory: HomeEnergyFlowHistory
  ) -> HomeEnergyFlowHistory {
    let mergedEnd = max(interval.end, liveHistory.interval.end)
    let mergedStart = mergedEnd.addingTimeInterval(-24 * 60 * 60)
    let liveReadings = liveHistory.readings.filter {
      $0.timestamp >= mergedStart && $0.timestamp <= mergedEnd
    }
    let merged = HomeEnergyFlowHistory(
      interval: DateInterval(start: interval.start, end: mergedEnd),
      readings: sorted(readings + liveReadings)
    )
    return HomeEnergyFlowHistory(
      interval: DateInterval(start: mergedStart, end: mergedEnd),
      readings: merged.readingsPreservingValues(at: mergedStart)
    )
  }

  private func readingsPreservingValues(at start: Date) -> [Reading] {
    var retained = readings.filter { $0.timestamp >= start }
    for series in Series.allCases {
      guard
        !retained.contains(where: {
          $0.series == series && $0.timestamp == start
        }),
        let active = readings.last(where: {
          $0.series == series && $0.timestamp < start
        })
      else {
        continue
      }
      retained.append(
        Reading(
          series: series,
          timestamp: start,
          kilowatts: active.kilowatts
        )
      )
    }
    return sorted(retained)
  }

  private func sorted(_ readings: [Reading]) -> [Reading] {
    Dictionary(readings.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
      .values
      .sorted { lhs, rhs in
        if lhs.timestamp == rhs.timestamp {
          return lhs.series.rawValue < rhs.series.rawValue
        }
        return lhs.timestamp < rhs.timestamp
      }
  }

  private func append(
    _ value: Double?,
    series: Series,
    at timestamp: Date,
    to readings: inout [Reading]
  ) {
    if let value, value.isFinite {
      guard
        readings.last(where: { $0.series == series })?.kilowatts != value
      else {
        return
      }
      readings.append(
        Reading(series: series, timestamp: timestamp, kilowatts: value)
      )
    } else if !readings.contains(where: { $0.series == series })
      || readings.last(where: { $0.series == series })?.kilowatts != nil
    {
      readings.append(
        Reading(series: series, timestamp: timestamp, kilowatts: nil)
      )
    }
  }

  private func extend(_ readings: inout [Reading], to timestamp: Date) {
    guard
      let latest = readings.last,
      latest.timestamp < timestamp
    else {
      return
    }
    readings.append(
      Reading(
        series: latest.series,
        timestamp: timestamp,
        kilowatts: latest.kilowatts
      )
    )
  }
}

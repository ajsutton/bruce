import Foundation

struct HomeEnergyBatteryHistory: Equatable, Sendable {
  struct Reading: Equatable, Identifiable, Sendable {
    let timestamp: Date
    let stateOfCharge: Double?

    var id: Date {
      timestamp
    }
  }

  static let empty = HomeEnergyBatteryHistory(
    interval: DateInterval(start: .distantPast, duration: 0),
    readings: []
  )

  let interval: DateInterval
  let readings: [Reading]

  var hasReadings: Bool {
    readings.contains { $0.stateOfCharge != nil }
  }

  var readingsExtendingToIntervalEnd: [Reading] {
    guard
      let latest = readings.last,
      latest.timestamp < interval.end
    else {
      return readings
    }
    return readings + [
      Reading(
        timestamp: interval.end,
        stateOfCharge: latest.stateOfCharge
      )
    ]
  }

  var availableReadingSegments: [[Reading]] {
    var segments: [[Reading]] = []
    var currentSegment: [Reading] = []
    for reading in readings {
      if reading.stateOfCharge != nil {
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
    return segments
  }

  func recording(
    snapshot: HomeAssistantHomeEnergySnapshot,
    at timestamp: Date
  ) -> HomeEnergyBatteryHistory {
    let start = timestamp.addingTimeInterval(-24 * 60 * 60)
    var updatedReadings = readingsPreservingValue(at: start)
    if let value = snapshot.batteryStateOfCharge,
      value.isFinite,
      (0...100).contains(value),
      updatedReadings.last?.stateOfCharge != value
    {
      updatedReadings.append(
        Reading(timestamp: timestamp, stateOfCharge: value)
      )
    } else if snapshot.batteryStateOfCharge == nil,
      updatedReadings.isEmpty || updatedReadings.last?.stateOfCharge != nil
    {
      updatedReadings.append(
        Reading(timestamp: timestamp, stateOfCharge: nil)
      )
    }
    return HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, end: timestamp),
      readings: sorted(updatedReadings)
    )
  }

  func mergingLiveReadings(
    from liveHistory: HomeEnergyBatteryHistory
  ) -> HomeEnergyBatteryHistory {
    let mergedEnd = max(
      interval.end,
      liveHistory.interval.end
    )
    let mergedStart = mergedEnd.addingTimeInterval(-24 * 60 * 60)
    let liveReadings = liveHistory.readings.filter {
      $0.timestamp >= mergedStart && $0.timestamp <= mergedEnd
    }
    let merged = HomeEnergyBatteryHistory(
      interval: DateInterval(start: interval.start, end: mergedEnd),
      readings: sorted(readings + liveReadings)
    )
    return HomeEnergyBatteryHistory(
      interval: DateInterval(start: mergedStart, end: mergedEnd),
      readings: merged.readingsPreservingValue(at: mergedStart)
    )
  }

  private func readingsPreservingValue(at start: Date) -> [Reading] {
    var retained = readings.filter { $0.timestamp >= start }
    guard !retained.contains(where: { $0.timestamp == start }) else {
      return retained
    }
    guard let active = readings.last(where: { $0.timestamp < start }) else {
      return retained
    }
    retained.append(
      Reading(timestamp: start, stateOfCharge: active.stateOfCharge)
    )
    return sorted(retained)
  }

  private func sorted(_ readings: [Reading]) -> [Reading] {
    Dictionary(readings.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
      .values
      .sorted { $0.timestamp < $1.timestamp }
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
        timestamp: timestamp,
        stateOfCharge: latest.stateOfCharge
      )
    )
  }
}

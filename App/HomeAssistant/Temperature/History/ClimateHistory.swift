import Foundation

struct ClimateHistory: Equatable, Sendable {
  struct Frame: Equatable, Sendable {
    let timestamp: Date
    let values: [String: ClimateHistoryValue]

    init(timestamp: Date, values: [String: ClimateHistoryValue]) {
      self.timestamp = timestamp
      self.values = values
    }

    init(timestamp: Date, states: [HomeAssistantState]) {
      self.timestamp = timestamp
      let indexed = Dictionary(
        states.map { ($0.entityID, $0) }, uniquingKeysWith: { _, new in new })
      values = Dictionary(
        uniqueKeysWithValues: ClimateHistoryZone.all.map {
          ($0.id, ClimateHistoryValue(zone: $0, states: indexed))
        })
    }

    func hasSemanticChange(from previous: Self) -> Bool {
      ClimateHistoryZone.all.contains {
        (values[$0.id] ?? .unknown).hasSemanticChange(from: previous.values[$0.id] ?? .unknown)
      }
    }
  }

  var interval: DateInterval
  var frames: [Frame]

  var hasValues: Bool {
    frames.contains { $0.values.values.contains { $0.actual != nil || $0.target != nil } }
  }

  mutating func append(_ frame: Frame, duration: TimeInterval) {
    guard frame.timestamp >= interval.end else { return }
    if frames.last?.timestamp == frame.timestamp { frames.removeLast() }
    frames.append(frame)
    interval = DateInterval(
      start: frame.timestamp.addingTimeInterval(-duration), end: frame.timestamp)
    if let boundary = frames.lastIndex(where: { $0.timestamp <= interval.start }), boundary > 0 {
      frames.removeFirst(boundary)
    }
  }

  func window(duration: TimeInterval) -> Self {
    let start = interval.end.addingTimeInterval(-duration)
    var visible = frames
    if let boundary = visible.lastIndex(where: { $0.timestamp <= start }), boundary > 0 {
      visible.removeFirst(boundary)
    }
    return Self(interval: DateInterval(start: start, end: interval.end), frames: visible)
  }

  func mergingEarlierHistory(_ earlier: Self?, duration: TimeInterval) -> Self {
    let start = interval.end.addingTimeInterval(-duration)
    guard let earlier, earlier.interval.end > start else { return self }
    var retained = earlier.frames.filter { $0.timestamp < interval.start }
    if let boundary = retained.lastIndex(where: { $0.timestamp <= start }), boundary > 0 {
      retained.removeFirst(boundary)
    }
    let backfill = frames.isEmpty ? [Frame(timestamp: interval.start, values: [:])] : frames
    return Self(
      interval: DateInterval(start: start, end: interval.end), frames: retained + backfill)
  }

  func points(for zone: ClimateHistoryZone) -> [ClimateHistoryPoint] {
    var points = frames.map {
      ClimateHistoryPoint(
        timestamp: max($0.timestamp, interval.start), value: $0.values[zone.id] ?? .unknown)
    }
    if let last = points.last, last.timestamp < interval.end {
      points.append(ClimateHistoryPoint(timestamp: interval.end, value: last.value))
    }
    return points
  }
}

struct ClimateHistoryPoint: Equatable, Identifiable, Sendable {
  let timestamp: Date
  let value: ClimateHistoryValue
  var id: Date { timestamp }
}

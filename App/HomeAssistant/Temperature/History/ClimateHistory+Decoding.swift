import Foundation

extension ClimateHistory {
  init(data: Data, interval: DateInterval) throws {
    let groups: [[HomeAssistantState]]
    do {
      groups = try JSONDecoder().decode([[HomeAssistantState]].self, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }
    let expected = Set(ClimateHistoryZone.entityIDs)
    guard
      groups.allSatisfy({ group in
        group.allSatisfy { expected.contains($0.entityID) && $0.lastUpdated != nil }
          && Set(group.map(\.entityID)).count <= 1
      })
    else { throw HomeAssistantAPIError.invalidResponse }
    let events = groups.flatMap { $0 }.filter { ($0.lastUpdated ?? .distantFuture) <= interval.end }
    let batches = Dictionary(grouping: events) {
      max($0.lastUpdated ?? interval.start, interval.start)
    }
    var states: [String: HomeAssistantState] = [:]
    var frames: [Frame] = []
    for timestamp in batches.keys.sorted() {
      for state in (batches[timestamp] ?? []).sorted(by: {
        ($0.lastUpdated ?? .distantPast) < ($1.lastUpdated ?? .distantPast)
      }) {
        states[state.entityID] = state
      }
      let values = Dictionary(
        uniqueKeysWithValues: ClimateHistoryZone.all.map {
          ($0.id, ClimateHistoryValue(zone: $0, states: states))
        })
      let frame = Frame(timestamp: timestamp, values: values)
      if frame.values != frames.last?.values { frames.append(frame) }
    }
    self.interval = interval
    self.frames = Self.coalesced(frames, spacing: max(interval.duration / 600, 5))
  }
  private static func coalesced(_ frames: [Frame], spacing: TimeInterval) -> [Frame] {
    var result: [Frame] = []
    var pending: Frame?
    for frame in frames {
      guard let previous = result.last else {
        result.append(frame)
        continue
      }
      if frame.hasSemanticChange(from: pending ?? previous) {
        if let pending { result.append(pending) }
        result.append(frame)
        pending = nil
      } else if frame.timestamp.timeIntervalSince(previous.timestamp) >= spacing {
        result.append(frame)
        pending = nil
      } else {
        pending = frame
      }
    }
    if let pending { result.append(pending) }
    return result
  }
}

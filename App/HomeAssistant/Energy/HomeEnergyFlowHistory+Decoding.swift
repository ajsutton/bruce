import Foundation

extension HomeEnergyFlowHistory {
  init(
    data: Data,
    interval: DateInterval,
    sampleInterval: TimeInterval = HomeEnergyHistorySampling.interval
  ) throws {
    let groups: [[FlowHistoryState]]
    do {
      groups = try JSONDecoder().decode([[FlowHistoryState]].self, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }

    var decodedReadings: [Reading] = []
    for group in groups {
      guard
        let entityID = group.first?.entityID,
        let series = FlowHistoryState.series(for: entityID)
      else {
        throw HomeAssistantAPIError.invalidResponse
      }
      guard group.allSatisfy({ $0.entityID == nil || $0.entityID == entityID }) else {
        throw HomeAssistantAPIError.invalidResponse
      }
      decodedReadings.append(
        contentsOf: Self.sampledReadings(
          from: group,
          series: series,
          interval: interval,
          sampleInterval: sampleInterval
        )
      )
    }
    readings = decodedReadings.sorted { lhs, rhs in
      if lhs.timestamp == rhs.timestamp {
        return lhs.series.rawValue < rhs.series.rawValue
      }
      return lhs.timestamp < rhs.timestamp
    }
    self.interval = interval
  }

  private static func sampledReadings(
    from states: [FlowHistoryState],
    series: Series,
    interval: DateInterval,
    sampleInterval: TimeInterval
  ) -> [Reading] {
    let readings = orderedReadings(
      from: states,
      series: series,
      interval: interval
    )
    guard sampleInterval > 0 else {
      return readings
    }
    return coalescedReadings(
      readings,
      interval: interval,
      sampleInterval: sampleInterval
    )
  }

  private static func orderedReadings(
    from states: [FlowHistoryState],
    series: Series,
    interval: DateInterval
  ) -> [Reading] {
    let ordered =
      states
      .enumerated()
      .filter { $0.element.lastChanged <= interval.end }
      .sorted { lhs, rhs in
        if lhs.element.lastChanged == rhs.element.lastChanged {
          return lhs.offset < rhs.offset
        }
        return lhs.element.lastChanged < rhs.element.lastChanged
      }
      .map { _, state in
        let rawValue = Double(state.state).flatMap {
          $0.isFinite ? $0 : nil
        }
        return Reading(
          series: series,
          timestamp: max(state.lastChanged, interval.start),
          kilowatts: rawValue.flatMap { series.normalizedKilowatts(from: $0) }
        )
      }
    return Dictionary(
      ordered.map { ($0.timestamp, $0) },
      uniquingKeysWith: { _, latest in latest }
    )
    .values
    .sorted { $0.timestamp < $1.timestamp }
  }

  private static func coalescedReadings(
    _ readings: [Reading],
    interval: DateInterval,
    sampleInterval: TimeInterval
  ) -> [Reading] {
    var sampled: [Reading] = []
    var pending: Reading?
    var pendingWindow: Int?
    var previousWasAvailable: Bool?

    for reading in readings {
      let isAvailable = reading.kilowatts != nil
      if reading.timestamp == interval.start, sampled.isEmpty {
        sampled.append(reading)
        previousWasAvailable = isAvailable
        continue
      }

      let window = Int(
        reading.timestamp.timeIntervalSince(interval.start) / sampleInterval
      )
      if let previousWasAvailable, previousWasAvailable != isAvailable {
        appendPending(&pending, to: &sampled)
        sampled.append(reading)
        pendingWindow = window
      } else {
        if let pendingWindow, pendingWindow != window {
          appendPending(&pending, to: &sampled)
        }
        pending = reading
        pendingWindow = window
      }
      previousWasAvailable = isAvailable
    }
    appendPending(&pending, to: &sampled)
    return Dictionary(
      sampled.map { ($0.id, $0) },
      uniquingKeysWith: { _, latest in latest }
    )
    .values
    .sorted { $0.timestamp < $1.timestamp }
  }

  private static func appendPending(
    _ pending: inout Reading?,
    to readings: inout [Reading]
  ) {
    guard let value = pending else { return }
    readings.append(value)
    pending = nil
  }
}

extension HomeEnergyFlowHistory.Series {
  fileprivate func normalizedKilowatts(from rawValue: Double) -> Double? {
    switch self {
    case .pvGeneration, .homeUsage:
      rawValue >= 0 ? rawValue : nil
    case .grid:
      rawValue
    case .battery:
      -rawValue
    }
  }
}

private struct FlowHistoryState: Decodable {
  let entityID: String?
  let state: String
  let lastChanged: Date

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case state
    case lastChanged = "last_changed"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    entityID = try container.decodeIfPresent(String.self, forKey: .entityID)
    state = try container.decode(String.self, forKey: .state)
    let timestamp = try container.decode(String.self, forKey: .lastChanged)
    guard let date = Self.date(from: timestamp) else {
      throw DecodingError.dataCorruptedError(
        forKey: .lastChanged,
        in: container,
        debugDescription: "Expected an ISO 8601 Home Assistant timestamp."
      )
    }
    lastChanged = date
  }

  static func series(for entityID: String) -> HomeEnergyFlowHistory.Series? {
    switch entityID {
    case HomeAssistantHomeEnergySnapshot.pvPowerEntityID:
      .pvGeneration
    case HomeAssistantHomeEnergySnapshot.homeConsumptionEntityID:
      .homeUsage
    case HomeAssistantHomeEnergySnapshot.gridPowerEntityID:
      .grid
    case HomeAssistantHomeEnergySnapshot.batteryPowerEntityID:
      .battery
    default:
      nil
    }
  }

  private static func date(from value: String) -> Date? {
    if let date = try? Date(
      value,
      strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    ) {
      return date
    }
    return try? Date(
      value,
      strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    )
  }
}

import Foundation

extension HomeEnergyPriceHistory {
  init(data: Data, interval: DateInterval) throws {
    let groups: [[HistoryState]]
    do {
      groups = try JSONDecoder().decode([[HistoryState]].self, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }

    var decodedReadings: [Reading.ID: Reading] = [:]
    for group in groups {
      guard
        let entityID = group.first?.entityID,
        let tariff = HistoryState.tariff(for: entityID)
      else {
        throw HomeAssistantAPIError.invalidResponse
      }
      guard group.allSatisfy({ $0.entityID == nil || $0.entityID == entityID }) else {
        throw HomeAssistantAPIError.invalidResponse
      }
      for state in group {
        guard
          state.lastChanged <= interval.end
        else {
          continue
        }
        let value = Double(state.state).flatMap {
          $0.isFinite ? $0 : nil
        }
        let reading = Reading(
          tariff: tariff,
          timestamp: max(state.lastChanged, interval.start),
          dollarsPerKilowattHour: value
        )
        decodedReadings[reading.id] = reading
      }
    }
    readings = decodedReadings.values.sorted { lhs, rhs in
      if lhs.timestamp == rhs.timestamp {
        return lhs.tariff.rawValue < rhs.tariff.rawValue
      }
      return lhs.timestamp < rhs.timestamp
    }
    self.interval = interval
  }
}

private struct HistoryState: Decodable {
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

  static func tariff(for entityID: String) -> HomeEnergyPriceHistory.Tariff? {
    switch entityID {
    case HomeAssistantHomeEnergySnapshot.generalPriceEntityID:
      .general
    case HomeAssistantHomeEnergySnapshot.feedInPriceEntityID:
      .feedIn
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

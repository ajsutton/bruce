import Foundation

extension HomeEnergyBatteryHistory {
  init(data: Data, interval: DateInterval) throws {
    let groups: [[BatteryHistoryState]]
    do {
      groups = try JSONDecoder().decode([[BatteryHistoryState]].self, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }

    let expectedEntityID =
      HomeAssistantHomeEnergySnapshot.batteryStateOfChargeEntityID
    guard
      groups.allSatisfy({ group in
        guard group.first?.entityID == expectedEntityID else { return false }
        return group.allSatisfy {
          $0.entityID == nil || $0.entityID == expectedEntityID
        }
      })
    else {
      throw HomeAssistantAPIError.invalidResponse
    }

    var decodedReadings: [Reading.ID: Reading] = [:]
    for state in groups.flatMap({ $0 }) {
      guard state.lastChanged <= interval.end else { continue }
      let value = Double(state.state).flatMap {
        $0.isFinite && (0...100).contains($0) ? $0 : nil
      }
      let reading = Reading(
        timestamp: max(state.lastChanged, interval.start),
        stateOfCharge: value
      )
      decodedReadings[reading.id] = reading
    }
    readings = decodedReadings.values.sorted { $0.timestamp < $1.timestamp }
    self.interval = interval
  }
}

private struct BatteryHistoryState: Decodable {
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

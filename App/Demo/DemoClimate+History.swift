import Foundation

extension DemoClimate: HomeAssistantStateLoading, ClimateHistoryLoading {
  func stateUpdates() async -> HomeAssistantBufferedUpdateStream<HomeAssistantStateUpdate> {
    HomeAssistantBufferedUpdateStream { continuation in
      let task = Task {
        do {
          for try await update in temperatureUpdates() {
            if case .live(let readings) = update {
              let data = try JSONEncoder().encode(readings.map(DemoClimateState.init))
              let states = try JSONDecoder().decode([HomeAssistantState].self, from: data)
              continuation.yield(.live(states))
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func loadClimateHistory(interval: DateInterval) async throws -> ClimateHistory {
    try Task.checkCancellation()
    return ClimateHistory(
      interval: interval,
      frames: (0...48).map { index in
        let values = Dictionary(
          uniqueKeysWithValues: ClimateHistoryZone.all.map { zone in
            (
              zone.id,
              ClimateHistoryValue(
                actual: 24 - sin(Double(index) / 12) * 1.5,
                target: zone.id == "climate.master_bed" ? 21 : 22,
                opening: 60, activity: .active
              )
            )
          })
        return ClimateHistory.Frame(
          timestamp: interval.start.addingTimeInterval(interval.duration * Double(index) / 48),
          values: values
        )
      }
    )
  }
}

private struct DemoClimateState: Encodable {

  let entityID: String
  let state: String
  let attributes: DemoClimateAttributes

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case state, attributes
  }

  init(_ reading: HomeAssistantTemperatureReading) {
    entityID = reading.id
    state = reading.powerState == .off ? "off" : "cool"
    attributes = DemoClimateAttributes(
      currentTemperature: reading.value, temperature: reading.targetValue)
  }
}

private struct DemoClimateAttributes: Encodable {
  let currentTemperature: Double?

  enum CodingKeys: String, CodingKey {
    case currentTemperature = "current_temperature"
    case temperature
  }
  let temperature: Double?
}

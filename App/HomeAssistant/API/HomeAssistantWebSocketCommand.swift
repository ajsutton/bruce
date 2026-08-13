import Foundation

struct HomeAssistantWebSocketCommand: Sendable {
  let type: String
  let fields: Fields

  enum Fields: Sendable {
    case none
    case statistics(start: String, end: String, statisticIDs: [String])
  }

  init(type: String, fields: Fields = .none) {
    self.type = type
    self.fields = fields
  }

  func data(id: Int) throws -> Data {
    var object: [String: Any] = ["id": id, "type": type]
    if case .statistics(let start, let end, let statisticIDs) = fields {
      object["start_time"] = start
      object["end_time"] = end
      object["statistic_ids"] = statisticIDs
      object["period"] = "day"
      object["types"] = ["change", "last_reset", "state"]
    }
    return try JSONSerialization.data(withJSONObject: object)
  }
}

protocol HomeAssistantWebSocketCommanding: Sendable {
  func perform(_ command: HomeAssistantWebSocketCommand) async throws -> Data
}

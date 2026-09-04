import Foundation

struct HomeAssistantWebSocketCommand: Sendable {
  enum StatisticsPeriod: String, Sendable {
    case fiveMinutes = "5minute"
  }

  let type: String
  let fields: Fields

  enum Fields: Sendable {
    case none
    case statistic(
      start: String,
      end: String,
      statisticID: String
    )
    case statistics(
      start: String,
      end: String,
      statisticIDs: [String],
      period: StatisticsPeriod,
      types: [String]
    )
  }

  init(type: String, fields: Fields = .none) {
    self.type = type
    self.fields = fields
  }

  func data(id: Int) throws -> Data {
    var object: [String: Any] = ["id": id, "type": type]
    switch fields {
    case .none:
      break
    case .statistic(let start, let end, let statisticID):
      object["fixed_period"] = [
        "start_time": start,
        "end_time": end,
      ]
      object["statistic_id"] = statisticID
      object["types"] = ["change"]
    case .statistics(let start, let end, let statisticIDs, let period, let types):
      object["start_time"] = start
      object["end_time"] = end
      object["statistic_ids"] = statisticIDs
      object["period"] = period.rawValue
      object["types"] = types
    }
    return try JSONSerialization.data(withJSONObject: object)
  }
}

protocol HomeAssistantWebSocketCommanding: Sendable {
  func perform(_ command: HomeAssistantWebSocketCommand) async throws -> Data
}

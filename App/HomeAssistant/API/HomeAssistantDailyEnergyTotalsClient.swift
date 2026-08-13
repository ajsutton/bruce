import Foundation

struct HomeAssistantDailyEnergyTotalsClient:
  HomeAssistantDailyEnergyTotalsLoading
{
  private let commands: any HomeAssistantWebSocketCommanding
  private let now: @Sendable () -> Date

  init(
    commands: any HomeAssistantWebSocketCommanding,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.commands = commands
    self.now = now
  }

  func loadDailyEnergyTotals() async throws -> HomeAssistantDailyEnergyTotals {
    let timestamp = now()
    let response = try await requestStatistics(
      from: timestamp.addingTimeInterval(-36 * 60 * 60), through: timestamp
    )
    return try Self.totals(from: response, at: timestamp)
  }

  static func totals(
    from statistics: [String: [HomeAssistantEnergyStatistic]],
    at timestamp: Date
  ) throws -> HomeAssistantDailyEnergyTotals {
    let importStatistic = currentStatistic(
      in: statistics[HomeAssistantHomeEnergySnapshot.importCostEntityID],
      at: timestamp
    )
    let exportStatistic = currentStatistic(
      in: statistics[HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID],
      at: timestamp
    )
    guard let interval = try sharedInterval(importStatistic, exportStatistic) else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return HomeAssistantDailyEnergyTotals(
      importCostDollars: try validatedChange(importStatistic),
      feedInEarningsDollars: try validatedChange(exportStatistic),
      interval: interval,
      importCounter: try validatedCounter(importStatistic),
      feedInCounter: try validatedCounter(exportStatistic)
    )
  }

  private static func currentStatistic(
    in statistics: [HomeAssistantEnergyStatistic]?,
    at timestamp: Date
  ) -> HomeAssistantEnergyStatistic? {
    statistics?.last {
      $0.start <= timestamp && timestamp < $0.end
    }
  }

  private static func sharedInterval(
    _ first: HomeAssistantEnergyStatistic?,
    _ second: HomeAssistantEnergyStatistic?
  ) throws -> DateInterval? {
    if let first, let second,
      first.start != second.start || first.end != second.end
    {
      throw HomeAssistantAPIError.invalidResponse
    }
    guard let statistic = first ?? second, statistic.start < statistic.end else {
      return nil
    }
    return DateInterval(start: statistic.start, end: statistic.end)
  }

  private static func validatedChange(
    _ statistic: HomeAssistantEnergyStatistic?
  ) throws -> Double? {
    guard let change = statistic?.change else { return nil }
    guard change.isFinite else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return change
  }

  private static func validatedCounter(
    _ statistic: HomeAssistantEnergyStatistic?
  ) throws -> HomeAssistantEnergyCounterReference? {
    guard let state = statistic?.state else { return nil }
    guard state.isFinite else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return HomeAssistantEnergyCounterReference(
      value: state,
      lastReset: statistic?.lastReset
    )
  }

  private func requestStatistics(
    from start: Date,
    through end: Date
  ) async throws -> [String: [HomeAssistantEnergyStatistic]] {
    let format = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    let data = try await commands.perform(
      HomeAssistantWebSocketCommand(
        type: "recorder/statistics_during_period",
        fields: .statistics(
          start: start.formatted(format),
          end: end.formatted(format),
          statisticIDs: [
            HomeAssistantHomeEnergySnapshot.importCostEntityID,
            HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID,
          ]
        )
      )
    )
    let response = try decode(
      HomeAssistantEnergyStatisticsResponse.self,
      from: data
    )
    guard response.type == "result", response.success,
      let result = response.result
    else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return result
  }

  private func decode<Message: Decodable>(
    _ type: Message.Type,
    from data: Data
  ) throws -> Message {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }
  }
}

struct HomeAssistantEnergyStatistic: Decodable, Equatable, Sendable {
  let start: Date
  let end: Date
  let change: Double?
  let state: Double?
  let lastReset: Date?

  enum CodingKeys: String, CodingKey {
    case start
    case end
    case change
    case state
    case lastReset = "last_reset"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    start = Date(
      timeIntervalSince1970:
        try container.decode(Double.self, forKey: .start) / 1_000
    )
    end = Date(
      timeIntervalSince1970:
        try container.decode(Double.self, forKey: .end) / 1_000
    )
    change = try container.decodeIfPresent(Double.self, forKey: .change)
    state = try container.decodeIfPresent(Double.self, forKey: .state)
    lastReset = try container.decodeIfPresent(Double.self, forKey: .lastReset).map {
      Date(timeIntervalSince1970: $0 / 1_000)
    }
  }
}

private struct HomeAssistantEnergyStatisticsResponse: Decodable {
  let type: String
  let success: Bool
  let result: [String: [HomeAssistantEnergyStatistic]]?
}

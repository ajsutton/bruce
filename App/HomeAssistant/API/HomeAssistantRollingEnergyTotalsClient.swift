import Foundation

struct HomeAssistantRollingEnergyTotalsClient:
  HomeAssistantRollingEnergyTotalsLoading
{
  private static let rollingDuration: TimeInterval = 24 * 60 * 60
  private static let refreshInterval: TimeInterval = 15 * 60
  private static let counterLookback: TimeInterval = 15 * 60
  private static let allowedRecorderLag: TimeInterval = 10 * 60

  private let commands: any HomeAssistantWebSocketCommanding
  private let now: @Sendable () -> Date

  init(
    commands: any HomeAssistantWebSocketCommanding,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.commands = commands
    self.now = now
  }

  func loadRollingEnergyTotals() async throws -> HomeAssistantRollingEnergyTotals {
    let timestamp = now()
    let counters = try await requestCounterStatistics(
      from: timestamp.addingTimeInterval(-Self.counterLookback),
      through: timestamp
    )
    let importStatistics = try Self.counterStatistics(
      counters[HomeAssistantHomeEnergySnapshot.importCostEntityID],
      at: timestamp
    )
    let feedInStatistics = try Self.counterStatistics(
      counters[HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID],
      at: timestamp
    )
    let hasImportCounter = try Self.hasValidCounter(importStatistics.last)
    let hasFeedInCounter = try Self.hasValidCounter(feedInStatistics.last)
    let importCost: Double?
    if let statistic = importStatistics.last, hasImportCounter {
      importCost = try await requestTotal(
        for: HomeAssistantHomeEnergySnapshot.importCostEntityID,
        from: statistic.end.addingTimeInterval(-Self.rollingDuration),
        through: statistic.end
      )
    } else {
      importCost = nil
    }
    let feedInEarnings: Double?
    if let statistic = feedInStatistics.last, hasFeedInCounter {
      feedInEarnings = try await requestTotal(
        for: HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID,
        from: statistic.end.addingTimeInterval(-Self.rollingDuration),
        through: statistic.end
      )
    } else {
      feedInEarnings = nil
    }
    return try Self.totals(
      importCost: importCost,
      feedInEarnings: feedInEarnings,
      importCapturedAt: importStatistics.last?.end,
      feedInCapturedAt: feedInStatistics.last?.end,
      at: timestamp
    )
  }

  static func totals(
    importCost: Double?,
    feedInEarnings: Double?,
    importCapturedAt: Date? = nil,
    feedInCapturedAt: Date? = nil,
    at timestamp: Date
  ) throws -> HomeAssistantRollingEnergyTotals {
    guard importCost != nil || feedInEarnings != nil else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return HomeAssistantRollingEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: feedInEarnings,
      refreshAfter: timestamp.addingTimeInterval(refreshInterval),
      importCapturedAt: importCapturedAt,
      feedInCapturedAt: feedInCapturedAt
    )
  }

  private static func counterStatistics(
    _ statistics: [HomeAssistantEnergyStatistic]?,
    at timestamp: Date
  ) throws -> [HomeAssistantEnergyStatistic] {
    let relevant =
      statistics?.filter {
        timestamp.addingTimeInterval(-counterLookback) <= $0.start
          && timestamp.addingTimeInterval(-allowedRecorderLag) <= $0.end
          && $0.start < timestamp
      } ?? []
    let sorted = relevant.sorted { $0.start < $1.start }
    guard
      sorted.allSatisfy({ $0.start < $0.end && $0.end <= timestamp }),
      zip(sorted, sorted.dropFirst()).allSatisfy({ $0.end <= $1.start })
    else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return sorted
  }

  private static func hasValidCounter(
    _ statistic: HomeAssistantEnergyStatistic?
  ) throws -> Bool {
    guard let state = statistic?.state else { return false }
    guard state.isFinite else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return true
  }

  private func requestTotal(
    for statisticID: String,
    from start: Date,
    through end: Date
  ) async throws -> Double? {
    let format = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    let data = try await commands.perform(
      HomeAssistantWebSocketCommand(
        type: "recorder/statistic_during_period",
        fields: .statistic(
          start: start.formatted(format),
          end: end.formatted(format),
          statisticID: statisticID
        )
      )
    )
    let response = try decode(HomeAssistantEnergyTotalResponse.self, from: data)
    guard response.type == "result", response.success, let result = response.result else {
      throw HomeAssistantAPIError.invalidResponse
    }
    guard let change = result.change else { return nil }
    guard change.isFinite else { throw HomeAssistantAPIError.invalidResponse }
    return change
  }

  private func requestCounterStatistics(
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
          ],
          period: .fiveMinutes,
          types: ["state"]
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

private struct HomeAssistantEnergyTotalResponse: Decodable {
  struct Result: Decodable {
    let change: Double?
  }

  let type: String
  let success: Bool
  let result: Result?
}

struct HomeAssistantEnergyStatistic: Decodable, Equatable, Sendable {
  let start: Date
  let end: Date
  let state: Double?

  enum CodingKeys: String, CodingKey {
    case start
    case end
    case state
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
    state = try container.decodeIfPresent(Double.self, forKey: .state)
  }
}

private struct HomeAssistantEnergyStatisticsResponse: Decodable {
  let type: String
  let success: Bool
  let result: [String: [HomeAssistantEnergyStatistic]]?
}

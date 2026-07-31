import Foundation

struct HomeAssistantDailyEnergyTotalsClient:
  HomeAssistantDailyEnergyTotalsLoading
{
  private let session: HomeAssistantSession
  private let connector: any HomeAssistantWebSocketConnecting
  private let now: @Sendable () -> Date

  init(
    session: HomeAssistantSession,
    connector: any HomeAssistantWebSocketConnecting =
      URLSessionWebSocketConnector(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.session = session
    self.connector = connector
    self.now = now
  }

  func loadDailyEnergyTotals() async throws -> HomeAssistantDailyEnergyTotals {
    let access = try await session.authenticatedWebSocketAccess()
    try Task.checkCancellation()
    let connection = connector.connect(to: access.url)
    return try await withTaskCancellationHandler {
      defer {
        connection.cancel()
      }
      try await authenticate(connection, accessToken: access.accessToken)
      let timestamp = now()
      let response = try await requestStatistics(
        from: timestamp.addingTimeInterval(-36 * 60 * 60),
        through: timestamp,
        over: connection
      )
      try await session.validateWebSocketAccess(access)
      try await session.rememberSuccessfulWebSocketAccess(access)
      return try Self.totals(from: response, at: timestamp)
    } onCancel: {
      connection.cancel()
    }
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

  private func authenticate(
    _ connection: any HomeAssistantWebSocketConnection,
    accessToken: String
  ) async throws {
    let required = try decode(
      HomeAssistantEnergyMessageKind.self,
      from: try await connection.receive()
    )
    guard required.type == "auth_required" else {
      throw HomeAssistantAPIError.invalidResponse
    }
    try await send(
      HomeAssistantEnergyAuthentication(
        type: "auth",
        accessToken: accessToken
      ),
      over: connection
    )
    let authentication = try decode(
      HomeAssistantEnergyMessageKind.self,
      from: try await connection.receive()
    )
    guard authentication.type == "auth_ok" else {
      if authentication.type == "auth_invalid" {
        throw HomeAssistantAPIError.unauthorized
      }
      throw HomeAssistantAPIError.invalidResponse
    }
  }

  private func requestStatistics(
    from start: Date,
    through end: Date,
    over connection: any HomeAssistantWebSocketConnection
  ) async throws -> [String: [HomeAssistantEnergyStatistic]] {
    let format = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    try await send(
      HomeAssistantEnergyStatisticsRequest(
        id: 1,
        type: "recorder/statistics_during_period",
        startTime: start.formatted(format),
        endTime: end.formatted(format),
        statisticIDs: [
          HomeAssistantHomeEnergySnapshot.importCostEntityID,
          HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID,
        ],
        period: "day",
        types: ["change", "last_reset", "state"]
      ),
      over: connection
    )
    let response = try decode(
      HomeAssistantEnergyStatisticsResponse.self,
      from: try await connection.receive()
    )
    guard response.id == 1, response.type == "result", response.success,
      let result = response.result
    else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return result
  }

  private func send<Message: Encodable>(
    _ message: Message,
    over connection: any HomeAssistantWebSocketConnection
  ) async throws {
    try await connection.send(JSONEncoder().encode(message))
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

private struct HomeAssistantEnergyMessageKind: Decodable {
  let type: String
}

private struct HomeAssistantEnergyAuthentication: Encodable {
  let type: String
  let accessToken: String

  enum CodingKeys: String, CodingKey {
    case type
    case accessToken = "access_token"
  }
}

private struct HomeAssistantEnergyStatisticsRequest: Encodable {
  let id: Int
  let type: String
  let startTime: String
  let endTime: String
  let statisticIDs: [String]
  let period: String
  let types: [String]

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case startTime = "start_time"
    case endTime = "end_time"
    case statisticIDs = "statistic_ids"
    case period
    case types
  }
}

private struct HomeAssistantEnergyStatisticsResponse: Decodable {
  let id: Int
  let type: String
  let success: Bool
  let result: [String: [HomeAssistantEnergyStatistic]]?
}

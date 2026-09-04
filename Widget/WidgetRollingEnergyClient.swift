import Foundation

struct WidgetRollingEnergyTotals: Sendable {
  let importCostDollars: Double?
  let feedInEarningsDollars: Double?
  let importCapturedAt: Date?
  let feedInCapturedAt: Date?
  let importIsCurrent: Bool
  let feedInIsCurrent: Bool

  init(
    importCostDollars: Double?,
    feedInEarningsDollars: Double?,
    importCapturedAt: Date? = nil,
    feedInCapturedAt: Date? = nil,
    importIsCurrent: Bool = true,
    feedInIsCurrent: Bool = true
  ) {
    self.importCostDollars = importCostDollars
    self.feedInEarningsDollars = feedInEarningsDollars
    self.importCapturedAt = importCapturedAt
    self.feedInCapturedAt = feedInCapturedAt
    self.importIsCurrent = importIsCurrent
    self.feedInIsCurrent = feedInIsCurrent
  }
}

struct WidgetRollingEnergyClient: Sendable {
  private static let rollingDuration: TimeInterval = 24 * 60 * 60
  private static let counterLookback: TimeInterval = 15 * 60
  private static let allowedRecorderLag: TimeInterval = 10 * 60

  private let connect: @Sendable (URL) -> any WidgetEnergyWebSocketConnection
  private let now: @Sendable () -> Date
  private let waitForTimeout: @Sendable () async throws -> Void

  init(session: URLSession, now: @escaping @Sendable () -> Date) {
    connect = { URLSessionWidgetEnergyWebSocket(task: session.webSocketTask(with: $0)) }
    self.now = now
    waitForTimeout = { try await Task.sleep(for: .seconds(8)) }
  }

  init(
    connect: @escaping @Sendable (URL) -> any WidgetEnergyWebSocketConnection,
    now: @escaping @Sendable () -> Date,
    waitForTimeout: @escaping @Sendable () async throws -> Void
  ) {
    self.connect = connect
    self.now = now
    self.waitForTimeout = waitForTimeout
  }

  func loadTotals(
    using credentials: WidgetHomeAssistantCredentials
  ) async throws -> WidgetRollingEnergyTotals {
    var receivedUnauthorized = false
    for baseURL in credentials.candidateURLs {
      do {
        let totals = try await loadTotals(
          at: baseURL,
          accessToken: credentials.accessToken
        )
        BruceSharedHomeAssistant.rememberWidgetRoute(
          baseURL,
          for: credentials.sourceIdentifier
        )
        return totals
      } catch is CancellationError {
        throw CancellationError()
      } catch WidgetHomeEnergyError.unauthorized {
        receivedUnauthorized = true
      } catch {
        try Self.checkCancellation(error)
        continue
      }
    }
    if receivedUnauthorized {
      throw WidgetHomeEnergyError.unauthorized
    }
    throw WidgetHomeEnergyError.noReachableServer
  }

  private func loadTotals(
    at baseURL: URL,
    accessToken: String
  ) async throws -> WidgetRollingEnergyTotals {
    do {
      return try await withThrowingTaskGroup(of: WidgetRollingEnergyTotals.self) { group in
        group.addTask {
          try await requestTotals(at: baseURL, accessToken: accessToken)
        }
        group.addTask {
          try await waitForTimeout()
          throw WidgetHomeEnergyError.noReachableServer
        }
        guard let result = try await group.next() else {
          throw WidgetHomeEnergyError.noReachableServer
        }
        group.cancelAll()
        return result
      }
    } catch is CancellationError where !Task.isCancelled {
      throw WidgetHomeEnergyError.noReachableServer
    }
  }

  private func requestTotals(
    at baseURL: URL,
    accessToken: String
  ) async throws -> WidgetRollingEnergyTotals {
    try Task.checkCancellation()
    let connection = connect(try webSocketURL(from: baseURL))
    connection.resume()
    return try await withTaskCancellationHandler {
      defer { connection.cancel() }
      try await authenticate(connection, accessToken: accessToken)
      return try await requestStatistics(over: connection)
    } onCancel: {
      connection.cancel()
    }
  }

  private func authenticate(
    _ connection: any WidgetEnergyWebSocketConnection,
    accessToken: String
  ) async throws {
    let required = try decode(
      WidgetEnergyMessageKind.self,
      from: try await connection.receive()
    )
    guard required.type == "auth_required" else {
      throw WidgetHomeEnergyError.invalidResponse
    }
    try await send(
      WidgetEnergyAuthentication(type: "auth", accessToken: accessToken),
      over: connection
    )
    let authentication = try decode(
      WidgetEnergyMessageKind.self,
      from: try await connection.receive()
    )
    guard authentication.type == "auth_ok" else {
      if authentication.type == "auth_invalid" {
        throw WidgetHomeEnergyError.unauthorized
      }
      throw WidgetHomeEnergyError.invalidResponse
    }
  }

  private func requestStatistics(
    over connection: any WidgetEnergyWebSocketConnection
  ) async throws -> WidgetRollingEnergyTotals {
    let timestamp = now()
    let counters = try await requestCounterStatistics(
      id: 1,
      from: timestamp.addingTimeInterval(-Self.counterLookback),
      through: timestamp,
      over: connection
    )
    let importStatistics = try Self.counterStatistics(
      counters[Self.importCostEntityID], at: timestamp)
    let feedInStatistics = try Self.counterStatistics(
      counters[Self.feedInEarningsEntityID],
      at: timestamp
    )
    let hasImportCounter = try Self.hasValidCounter(importStatistics.last)
    let hasFeedInCounter = try Self.hasValidCounter(feedInStatistics.last)
    let importCost: Double?
    if let statistic = importStatistics.last, hasImportCounter {
      importCost = try await requestTotal(
        id: 2,
        statisticID: Self.importCostEntityID,
        from: statistic.end.addingTimeInterval(-Self.rollingDuration),
        through: statistic.end,
        over: connection
      )
    } else {
      importCost = nil
    }
    let feedInEarnings: Double?
    if let statistic = feedInStatistics.last, hasFeedInCounter {
      feedInEarnings = try await requestTotal(
        id: 3,
        statisticID: Self.feedInEarningsEntityID,
        from: statistic.end.addingTimeInterval(-Self.rollingDuration),
        through: statistic.end,
        over: connection
      )
    } else {
      feedInEarnings = nil
    }
    return try Self.totals(
      importCost: importCost,
      feedInEarnings: feedInEarnings,
      importCapturedAt: importStatistics.last?.end,
      feedInCapturedAt: feedInStatistics.last?.end
    )
  }

  private func requestTotal(
    id: Int,
    statisticID: String,
    from start: Date,
    through end: Date,
    over connection: any WidgetEnergyWebSocketConnection
  ) async throws -> Double? {
    try await send(
      WidgetEnergyTotalRequest(
        id: id,
        type: "recorder/statistic_during_period",
        fixedPeriod: WidgetEnergyFixedPeriod(
          startTime: start.formatted(.iso8601),
          endTime: end.formatted(.iso8601)
        ),
        statisticID: statisticID,
        types: ["change"]
      ),
      over: connection
    )
    let response = try decode(
      WidgetEnergyTotalResponse.self,
      from: try await connection.receive()
    )
    guard response.id == id, response.type == "result", response.success,
      let result = response.result
    else {
      throw WidgetHomeEnergyError.invalidResponse
    }
    guard let change = result.change else { return nil }
    guard change.isFinite else { throw WidgetHomeEnergyError.invalidResponse }
    return change
  }

  private func requestCounterStatistics(
    id: Int,
    from start: Date,
    through end: Date,
    over connection: any WidgetEnergyWebSocketConnection
  ) async throws -> [String: [WidgetEnergyStatistic]] {
    try await send(
      WidgetEnergyStatisticsRequest(
        id: id,
        type: "recorder/statistics_during_period",
        startTime: start.formatted(.iso8601),
        endTime: end.formatted(.iso8601),
        statisticIDs: [Self.importCostEntityID, Self.feedInEarningsEntityID],
        period: "5minute",
        types: ["state"]
      ),
      over: connection
    )
    let response = try decode(
      WidgetEnergyStatisticsResponse.self,
      from: try await connection.receive()
    )
    guard response.id == id, response.type == "result", response.success,
      let result = response.result
    else {
      throw WidgetHomeEnergyError.invalidResponse
    }
    return result
  }

  static func totals(
    importCost: Double?,
    feedInEarnings: Double?,
    importCapturedAt: Date? = nil,
    feedInCapturedAt: Date? = nil
  ) throws -> WidgetRollingEnergyTotals {
    guard importCost != nil || feedInEarnings != nil else {
      throw WidgetHomeEnergyError.invalidResponse
    }
    return WidgetRollingEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: feedInEarnings,
      importCapturedAt: importCapturedAt,
      feedInCapturedAt: feedInCapturedAt,
      importIsCurrent: importCost != nil,
      feedInIsCurrent: feedInEarnings != nil
    )
  }
}

extension WidgetRollingEnergyClient {
  private func webSocketURL(from baseURL: URL) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw WidgetHomeEnergyError.invalidResponse
    }
    switch components.scheme?.lowercased() {
    case "http": components.scheme = "ws"
    case "https": components.scheme = "wss"
    default: throw WidgetHomeEnergyError.invalidResponse
    }
    let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    components.path =
      "/" + [basePath, "api/websocket"].filter { !$0.isEmpty }.joined(separator: "/")
    guard let url = components.url else {
      throw WidgetHomeEnergyError.invalidResponse
    }
    return url
  }

  private static func counterStatistics(
    _ statistics: [WidgetEnergyStatistic]?,
    at timestamp: Date
  ) throws -> [WidgetEnergyStatistic] {
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
      throw WidgetHomeEnergyError.invalidResponse
    }
    return sorted
  }

  private static func hasValidCounter(
    _ statistic: WidgetEnergyStatistic?
  ) throws -> Bool {
    guard let state = statistic?.state else { return false }
    guard state.isFinite else { throw WidgetHomeEnergyError.invalidResponse }
    return true
  }

  private func send<Message: Encodable>(
    _ message: Message,
    over connection: any WidgetEnergyWebSocketConnection
  ) async throws {
    try await connection.send(try JSONEncoder().encode(message))
  }

  private func decode<Message: Decodable>(
    _ type: Message.Type,
    from data: Data
  ) throws -> Message {
    guard let value = try? JSONDecoder().decode(type, from: data) else {
      throw WidgetHomeEnergyError.invalidResponse
    }
    return value
  }

  private static func checkCancellation(_ error: Error) throws {
    if Task.isCancelled || (error as? URLError)?.code == .cancelled {
      throw CancellationError()
    }
  }

  private static let importCostEntityID =
    "sensor.sigen_plant_total_imported_energy_cost"
  private static let feedInEarningsEntityID =
    "sensor.sigen_plant_total_exported_energy_compensation"
}

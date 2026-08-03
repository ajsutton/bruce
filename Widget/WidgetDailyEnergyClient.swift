import Foundation

struct WidgetDailyEnergyTotals: Sendable {
  let importCostDollars: Double?
  let feedInEarningsDollars: Double?
  let interval: DateInterval?
  let importCounter: WidgetEnergyCounterReference?
  let feedInCounter: WidgetEnergyCounterReference?
  let importIsCurrent: Bool
  let feedInIsCurrent: Bool

  init(
    importCostDollars: Double?,
    feedInEarningsDollars: Double?,
    interval: DateInterval? = nil,
    importCounter: WidgetEnergyCounterReference? = nil,
    feedInCounter: WidgetEnergyCounterReference? = nil,
    importIsCurrent: Bool = true,
    feedInIsCurrent: Bool = true
  ) {
    self.importCostDollars = importCostDollars
    self.feedInEarningsDollars = feedInEarningsDollars
    self.interval = interval
    self.importCounter = importCounter
    self.feedInCounter = feedInCounter
    self.importIsCurrent = importIsCurrent
    self.feedInIsCurrent = feedInIsCurrent
  }
}

struct WidgetEnergyCounterReference: Sendable {
  let value: Double
  let lastReset: Date?
}

struct WidgetDailyEnergyClient: Sendable {
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
  ) async throws -> WidgetDailyEnergyTotals {
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
  ) async throws -> WidgetDailyEnergyTotals {
    try await withThrowingTaskGroup(of: WidgetDailyEnergyTotals.self) { group in
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
  }

  private func requestTotals(
    at baseURL: URL,
    accessToken: String
  ) async throws -> WidgetDailyEnergyTotals {
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
  ) async throws -> WidgetDailyEnergyTotals {
    let timestamp = now()
    try await send(
      WidgetEnergyStatisticsRequest(
        id: 1,
        type: "recorder/statistics_during_period",
        startTime: timestamp.addingTimeInterval(-36 * 60 * 60).formatted(.iso8601),
        endTime: timestamp.formatted(.iso8601),
        statisticIDs: [Self.importCostEntityID, Self.feedInEarningsEntityID],
        period: "day",
        types: ["change", "last_reset", "state"]
      ),
      over: connection
    )
    let data = try await connection.receive()
    return try Self.totals(from: data, at: timestamp)
  }

  static func totals(from data: Data, at timestamp: Date) throws -> WidgetDailyEnergyTotals {
    guard let response = try? JSONDecoder().decode(WidgetEnergyStatisticsResponse.self, from: data)
    else {
      throw WidgetHomeEnergyError.invalidResponse
    }
    guard response.id == 1, response.type == "result", response.success,
      let result = response.result
    else {
      throw WidgetHomeEnergyError.invalidResponse
    }
    let importStatistic = currentStatistic(in: result[Self.importCostEntityID], at: timestamp)
    let feedInStatistic = currentStatistic(in: result[Self.feedInEarningsEntityID], at: timestamp)
    guard let interval = Self.sharedInterval(importStatistic, feedInStatistic) else {
      throw WidgetHomeEnergyError.invalidResponse
    }
    let importCost = try validatedChange(importStatistic)
    let feedInEarnings = try validatedChange(feedInStatistic)
    return WidgetDailyEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: feedInEarnings,
      interval: interval,
      importCounter: try validatedCounter(importStatistic),
      feedInCounter: try validatedCounter(feedInStatistic),
      importIsCurrent: importCost != nil,
      feedInIsCurrent: feedInEarnings != nil
    )
  }

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

  private static func currentStatistic(
    in statistics: [WidgetEnergyStatistic]?,
    at timestamp: Date
  ) -> WidgetEnergyStatistic? {
    statistics?.last {
      $0.start <= timestamp && timestamp < $0.end
    }
  }

  private static func sharedInterval(
    _ first: WidgetEnergyStatistic?,
    _ second: WidgetEnergyStatistic?
  ) -> DateInterval? {
    if let first, let second,
      first.start != second.start || first.end != second.end
    {
      return nil
    }
    guard let statistic = first ?? second, statistic.start < statistic.end else { return nil }
    return DateInterval(start: statistic.start, end: statistic.end)
  }

  private static func validatedChange(
    _ statistic: WidgetEnergyStatistic?
  ) throws -> Double? {
    guard let change = statistic?.change else { return nil }
    guard change.isFinite else { throw WidgetHomeEnergyError.invalidResponse }
    return change
  }

  private static func validatedCounter(
    _ statistic: WidgetEnergyStatistic?
  ) throws -> WidgetEnergyCounterReference? {
    guard let state = statistic?.state else { return nil }
    guard state.isFinite else { throw WidgetHomeEnergyError.invalidResponse }
    return WidgetEnergyCounterReference(value: state, lastReset: statistic?.lastReset)
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

protocol WidgetEnergyWebSocketConnection: Sendable {
  func resume()
  func send(_ data: Data) async throws
  func receive() async throws -> Data
  func cancel()
}

private final class URLSessionWidgetEnergyWebSocket:
  WidgetEnergyWebSocketConnection,
  @unchecked Sendable
{
  private let task: URLSessionWebSocketTask
  private let lock = NSLock()
  private var isCancelled = false

  init(task: URLSessionWebSocketTask) {
    self.task = task
  }

  func resume() {
    task.resume()
  }

  func send(_ data: Data) async throws {
    try await task.send(.data(data))
  }

  func receive() async throws -> Data {
    switch try await task.receive() {
    case .data(let data): data
    case .string(let string): Data(string.utf8)
    @unknown default: throw WidgetHomeEnergyError.invalidResponse
    }
  }

  func cancel() {
    let shouldCancel = lock.withLock {
      guard !isCancelled else { return false }
      isCancelled = true
      return true
    }
    if shouldCancel {
      task.cancel(with: .goingAway, reason: nil)
    }
  }
}

private struct WidgetEnergyMessageKind: Decodable {
  let type: String
}

private struct WidgetEnergyAuthentication: Encodable {
  let type: String
  let accessToken: String

  enum CodingKeys: String, CodingKey {
    case type
    case accessToken = "access_token"
  }
}

private struct WidgetEnergyStatisticsRequest: Encodable {
  let id: Int
  let type: String
  let startTime: String
  let endTime: String
  let statisticIDs: [String]
  let period: String
  let types: [String]

  enum CodingKeys: String, CodingKey {
    case id, type, period, types
    case startTime = "start_time"
    case endTime = "end_time"
    case statisticIDs = "statistic_ids"
  }
}

private struct WidgetEnergyStatisticsResponse: Decodable {
  let id: Int
  let type: String
  let success: Bool
  let result: [String: [WidgetEnergyStatistic]]?
}

private struct WidgetEnergyStatistic: Decodable {
  let start: Date
  let end: Date
  let change: Double?
  let state: Double?
  let lastReset: Date?

  enum CodingKeys: String, CodingKey {
    case start, end, change, state
    case lastReset = "last_reset"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    start = Date(
      timeIntervalSince1970: try container.decode(Double.self, forKey: .start) / 1_000
    )
    end = Date(
      timeIntervalSince1970: try container.decode(Double.self, forKey: .end) / 1_000
    )
    change = try container.decodeIfPresent(Double.self, forKey: .change)
    state = try container.decodeIfPresent(Double.self, forKey: .state)
    lastReset = try container.decodeIfPresent(Double.self, forKey: .lastReset).map {
      Date(timeIntervalSince1970: $0 / 1_000)
    }
  }
}

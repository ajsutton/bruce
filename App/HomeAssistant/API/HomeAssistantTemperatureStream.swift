import Foundation
import OSLog

struct HomeAssistantTemperatureStream: HomeAssistantTemperatureLoading {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.symphonious.bruce",
    category: "HomeAssistantTemperatureSubscription"
  )

  private let session: HomeAssistantSession
  private let apiClient: HomeAssistantAPIClient
  private let connector: any HomeAssistantWebSocketConnecting
  private let retryDelays: [Duration]
  private let sleep: @Sendable (Duration) async throws -> Void

  init(
    session: HomeAssistantSession,
    connector: any HomeAssistantWebSocketConnecting = URLSessionWebSocketConnector(),
    retryDelays: [Duration] = [
      .seconds(1),
      .seconds(2),
      .seconds(5),
      .seconds(10),
      .seconds(30),
    ],
    sleep: @escaping @Sendable (Duration) async throws -> Void = {
      try await Task.sleep(for: $0)
    }
  ) {
    self.session = session
    apiClient = HomeAssistantAPIClient(session: session)
    self.connector = connector
    self.retryDelays = retryDelays
    self.sleep = sleep
  }

  init(
    session: HomeAssistantSession,
    apiClient: HomeAssistantAPIClient,
    connector: any HomeAssistantWebSocketConnecting,
    retryDelays: [Duration],
    sleep: @escaping @Sendable (Duration) async throws -> Void
  ) {
    self.session = session
    self.apiClient = apiClient
    self.connector = connector
    self.retryDelays = retryDelays
    self.sleep = sleep
  }

  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task {
        await run(continuation)
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func run(
    _ continuation: AsyncThrowingStream<
      HomeAssistantTemperatureUpdate, any Error
    >.Continuation
  ) async {
    var retryIndex = 0
    var routeIndex = 0
    var latestReadings: [HomeAssistantTemperatureReading] = []
    while !Task.isCancelled {
      var publishedSnapshot = false
      var routeCount = 0
      do {
        let accesses = try await session.authenticatedWebSocketAccesses()
        guard !accesses.isEmpty else {
          throw HomeAssistantAPIError.invalidServerURL
        }
        routeCount = accesses.count
        let access = accesses[routeIndex % accesses.count]
        try await subscribe(using: access) { readings in
          publishedSnapshot = true
          latestReadings = readings
          continuation.yield(.live(readings))
        }
      } catch is CancellationError {
        continuation.finish()
        return
      } catch {
        guard Self.shouldReconnect(after: error), !retryDelays.isEmpty else {
          continuation.finish(throwing: error)
          return
        }
        if publishedSnapshot {
          retryIndex = 0
        }
        if routeCount > 0 {
          routeIndex = (routeIndex + 1) % routeCount
        }
        let delay = retryDelays[min(retryIndex, retryDelays.count - 1)]
        retryIndex = min(retryIndex + 1, retryDelays.count - 1)
        Self.logger.error(
          "Home Assistant temperature subscription disconnected: \(String(describing: error), privacy: .private)"
        )
        continuation.yield(.reconnecting(latestReadings))
        do {
          try await sleep(delay)
        } catch {
          continuation.finish()
          return
        }
      }
    }
    continuation.finish()
  }

  private func subscribe(
    using access: HomeAssistantWebSocketAccess,
    publish: ([HomeAssistantTemperatureReading]) -> Void
  ) async throws {
    let connection = connector.connect(to: access.url)
    try await withTaskCancellationHandler {
      defer {
        connection.cancel()
      }
      try await authenticate(connection, accessToken: access.accessToken)
      try await subscribeToStateChanges(over: connection)
      try await session.rememberSuccessfulWebSocketAccess(access)
      let snapshot = try await apiClient.loadTemperatureSnapshot()
      var readingsByID = Dictionary(
        uniqueKeysWithValues: snapshot.readings.map { ($0.id, $0) }
      )
      publish(Self.sorted(readingsByID.values))

      while !Task.isCancelled {
        let event = try decode(
          HomeAssistantStateChangedMessage.self,
          from: try await connection.receive()
        )
        guard event.id == 1, event.type == "event",
          event.event.eventType == "state_changed"
        else {
          throw HomeAssistantAPIError.invalidResponse
        }
        let entityID = event.event.data.entityID
        guard entityID.hasPrefix("climate.") else {
          continue
        }
        if let reading = event.event.data.newState?.temperatureReading(
          unit: snapshot.unit,
          registryIcon: snapshot.climateIcons[entityID]
        ) {
          readingsByID[entityID] = reading
        } else {
          readingsByID.removeValue(forKey: entityID)
        }
        publish(Self.sorted(readingsByID.values))
      }
      throw CancellationError()
    } onCancel: {
      connection.cancel()
    }
  }

  private func authenticate(
    _ connection: any HomeAssistantWebSocketConnection,
    accessToken: String
  ) async throws {
    let required = try decode(
      HomeAssistantSubscriptionMessageKind.self,
      from: try await connection.receive()
    )
    guard required.type == "auth_required" else {
      throw HomeAssistantAPIError.invalidResponse
    }
    try await send(
      HomeAssistantSubscriptionAuthentication(type: "auth", accessToken: accessToken),
      over: connection
    )
    let authentication = try decode(
      HomeAssistantSubscriptionMessageKind.self,
      from: try await connection.receive()
    )
    guard authentication.type == "auth_ok" else {
      if authentication.type == "auth_invalid" {
        throw HomeAssistantAPIError.unauthorized
      }
      throw HomeAssistantAPIError.invalidResponse
    }
  }

  private func subscribeToStateChanges(
    over connection: any HomeAssistantWebSocketConnection
  ) async throws {
    try await send(
      HomeAssistantStateChangedSubscription(
        id: 1,
        type: "subscribe_events",
        eventType: "state_changed"
      ),
      over: connection
    )
    let response = try decode(
      HomeAssistantSubscriptionResult.self,
      from: try await connection.receive()
    )
    guard response.id == 1, response.type == "result", response.success else {
      throw HomeAssistantAPIError.invalidResponse
    }
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

  private static func sorted(
    _ readings: Dictionary<String, HomeAssistantTemperatureReading>.Values
  ) -> [HomeAssistantTemperatureReading] {
    readings.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  private static func shouldReconnect(after error: any Error) -> Bool {
    guard let apiError = error as? HomeAssistantAPIError else {
      return true
    }
    switch apiError {
    case .server:
      return true
    case .noCredentials, .invalidServerURL, .unauthorized, .reauthenticationRequired,
      .incompatibleServer, .invalidResponse, .staleOperation:
      return false
    }
  }
}

private struct HomeAssistantSubscriptionMessageKind: Decodable {
  let type: String
}

private struct HomeAssistantSubscriptionAuthentication: Encodable {
  let type: String
  let accessToken: String

  enum CodingKeys: String, CodingKey {
    case type
    case accessToken = "access_token"
  }
}

private struct HomeAssistantStateChangedSubscription: Encodable {
  let id: Int
  let type: String
  let eventType: String

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case eventType = "event_type"
  }
}

private struct HomeAssistantSubscriptionResult: Decodable {
  let id: Int
  let type: String
  let success: Bool
}

private struct HomeAssistantStateChangedMessage: Decodable {
  let id: Int
  let type: String
  let event: HomeAssistantStateChangedEvent
}

private struct HomeAssistantStateChangedEvent: Decodable {
  let eventType: String
  let data: HomeAssistantStateChangedData

  enum CodingKeys: String, CodingKey {
    case eventType = "event_type"
    case data
  }
}

private struct HomeAssistantStateChangedData: Decodable {
  let entityID: String
  let newState: HomeAssistantState?

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case newState = "new_state"
  }
}

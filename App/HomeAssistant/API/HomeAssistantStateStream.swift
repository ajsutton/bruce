import Foundation
import OSLog

struct HomeAssistantStateStream: HomeAssistantStateLoading {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.symphonious.bruce",
    category: "HomeAssistantStateSubscription"
  )

  private let session: HomeAssistantSession
  private let apiClient: HomeAssistantAPIClient
  private let connector: any HomeAssistantWebSocketConnecting
  private let retryDelays: [Duration]
  private let sleep: @Sendable (Duration) async throws -> Void
  private let orderingCache = HomeAssistantStateOrderingCache()

  init(
    session: HomeAssistantSession,
    apiClient: HomeAssistantAPIClient? = nil,
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
    self.apiClient = apiClient ?? HomeAssistantAPIClient(session: session)
    self.connector = connector
    self.retryDelays = retryDelays
    self.sleep = sleep
  }

  func stateUpdates() async -> AsyncThrowingStream<
    HomeAssistantStateUpdate, any Error
  > {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task {
        do {
          try await run(continuation)
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func run(
    _ continuation: AsyncThrowingStream<
      HomeAssistantStateUpdate, any Error
    >.Continuation
  ) async throws {
    let observation = try await beginObservation()
    var retryIndex = 0
    var lastFailedURL: URL?
    var latestSnapshot = observation.snapshot
    while !Task.isCancelled {
      let generation = UUID()
      var publishedSnapshot = false
      var attemptedURL: URL?
      do {
        let accesses = try await session.authenticatedWebSocketAccesses()
        let access = try preferredAccess(from: accesses, avoiding: lastFailedURL)
        guard access.observationIdentity == observation.identity else {
          throw HomeAssistantAPIError.staleOperation
        }
        attemptedURL = access.baseURL
        try await subscribe(
          using: access,
          previousStates: latestSnapshot.states,
          previousRemovals: latestSnapshot.removals
        ) { states, removals in
          publishedSnapshot = true
          latestSnapshot = .init(states: states, removals: removals)
          try await cache(latestSnapshot, for: observation.id, access: access)
          Self.yieldLive(states, generation: generation, to: continuation)
        }
      } catch is CancellationError {
        continuation.finish()
        return
      } catch {
        guard Self.shouldReconnect(after: error), !retryDelays.isEmpty else {
          continuation.finish(throwing: error)
          return
        }
        retryIndex = publishedSnapshot ? 0 : retryIndex
        lastFailedURL = attemptedURL ?? lastFailedURL
        let delay = retryDelays[min(retryIndex, retryDelays.count - 1)]
        retryIndex = min(retryIndex + 1, retryDelays.count - 1)
        Self.reportDisconnect(
          error,
          update: .reconnecting(latestSnapshot.states, generation: generation),
          to: continuation
        )
        guard await waitForRetry(delay) else {
          continuation.finish()
          return
        }
      }
    }
    continuation.finish()
  }

  private func cache(
    _ snapshot: HomeAssistantStateOrderingCache.Snapshot,
    for observation: UUID,
    access: HomeAssistantWebSocketAccess
  ) async throws {
    try await session.validateWebSocketAccess(access)
    await orderingCache.store(snapshot, observation: observation)
    try await session.validateWebSocketAccess(access)
  }

  private func beginObservation() async throws -> HomeAssistantStateOrderingCache.Observation {
    let access = try await session.authenticatedWebSocketAccess()
    let observation = await orderingCache.beginObservation(for: access.observationIdentity)
    try await session.validateWebSocketAccess(access)
    return observation
  }

  private func preferredAccess(
    from accesses: [HomeAssistantWebSocketAccess],
    avoiding failedURL: URL?
  ) throws -> HomeAssistantWebSocketAccess {
    guard !accesses.isEmpty else {
      throw HomeAssistantAPIError.invalidServerURL
    }
    return accesses.first(where: { $0.baseURL != failedURL }) ?? accesses[0]
  }

  private func subscribe(
    using access: HomeAssistantWebSocketAccess,
    previousStates: [HomeAssistantState],
    previousRemovals: [String: Date],
    publish: ([HomeAssistantState], [String: Date]) async throws -> Void
  ) async throws {
    let connection = connector.connect(to: access.url)
    try await withTaskCancellationHandler {
      defer {
        connection.cancel()
      }
      try await authenticate(connection, accessToken: access.accessToken)
      try await subscribeToStateChanges(over: connection)
      try await session.rememberSuccessfulWebSocketAccess(access)
      var snapshot = try Self.mergedSnapshot(
        try await apiClient.loadHomeAssistantStates(),
        previousStates: previousStates,
        previousRemovals: previousRemovals
      )
      try await session.validateWebSocketAccess(access)
      try await publish(Self.sorted(snapshot.statesByID.values), snapshot.removals)

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
        try Self.apply(
          event.event.data,
          to: &snapshot.statesByID,
          removals: &snapshot.removals
        )
        try await publish(Self.sorted(snapshot.statesByID.values), snapshot.removals)
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
}

extension HomeAssistantStateStream {
  fileprivate static func yield(
    _ update: HomeAssistantStateUpdate,
    to continuation: AsyncThrowingStream<
      HomeAssistantStateUpdate, any Error
    >.Continuation
  ) {
    if case .dropped = continuation.yield(update) {
      continuation.yield(update.requiringHistoryBackfill())
    }
  }

  fileprivate static func yieldLive(
    _ states: [HomeAssistantState],
    generation: UUID,
    to continuation: AsyncThrowingStream<
      HomeAssistantStateUpdate, any Error
    >.Continuation
  ) {
    yield(.live(states, generation: generation), to: continuation)
  }

  fileprivate static func reportDisconnect(
    _ error: any Error,
    update: HomeAssistantStateUpdate,
    to continuation: AsyncThrowingStream<
      HomeAssistantStateUpdate, any Error
    >.Continuation
  ) {
    logger.error(
      "Home Assistant state subscription disconnected: \(String(describing: error), privacy: .private)"
    )
    yield(update, to: continuation)
  }

  fileprivate func waitForRetry(_ delay: Duration) async -> Bool {
    do {
      try await sleep(delay)
      return true
    } catch {
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

struct HomeAssistantStateChangedData: Decodable {
  let entityID: String
  let newState: HomeAssistantState?
  let oldState: HomeAssistantState?

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard container.contains(.newState), container.contains(.oldState) else {
      throw DecodingError.keyNotFound(
        container.contains(.newState) ? CodingKeys.oldState : CodingKeys.newState,
        .init(
          codingPath: container.codingPath,
          debugDescription: "State changes require both new_state and old_state."
        )
      )
    }
    entityID = try container.decode(String.self, forKey: .entityID)
    newState = try container.decodeIfPresent(HomeAssistantState.self, forKey: .newState)
    oldState = try container.decodeIfPresent(HomeAssistantState.self, forKey: .oldState)
  }

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case newState = "new_state"
    case oldState = "old_state"
  }
}

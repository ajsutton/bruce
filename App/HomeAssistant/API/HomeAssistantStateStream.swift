import Foundation

struct HomeAssistantStateStream: HomeAssistantStateLoading {
  let session: HomeAssistantSession
  private let apiClient: HomeAssistantAPIClient
  private let connector: any HomeAssistantWebSocketConnecting
  let retryDelays: [Duration]
  let sleep: @Sendable (Duration) async throws -> Void
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

  func stateUpdates() async -> HomeAssistantBufferedUpdateStream<
    HomeAssistantStateUpdate
  > {
    HomeAssistantBufferedUpdateStream { continuation in
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
    _ continuation: HomeAssistantBufferedUpdateStream<
      HomeAssistantStateUpdate
    >.Continuation
  ) async throws {
    let observation = try await beginObservation()
    var recoveryState = HomeAssistantReconnectState()
    var latestSnapshot = observation.snapshot
    var hasPublishedSnapshot = false
    while !Task.isCancelled {
      let generation = UUID()
      var publishedSnapshot = false
      var attemptedAccess: HomeAssistantWebSocketAccess?
      do {
        let accesses = try await session.authenticatedWebSocketAccesses()
        let access = try preferredAccess(
          from: accesses,
          avoiding: recoveryState.lastFailedURL
        )
        try validateObservation(access, identity: observation.identity)
        attemptedAccess = access
        try await subscribe(
          using: access,
          generation: generation,
          previousStates: latestSnapshot.states,
          previousRemovals: latestSnapshot.removals
        ) { states, removals, eventGeneration in
          (publishedSnapshot, hasPublishedSnapshot) = (true, true)
          recoveryState.refreshedAfterUnauthorized = false
          latestSnapshot = .init(states: states, removals: removals)
          try await cache(latestSnapshot, for: observation.id, access: access)
          Self.yieldLive(states, generation: eventGeneration, to: continuation)
        }
      } catch is CancellationError {
        continuation.finish()
        return
      } catch {
        let attempt = HomeAssistantReconnectAttempt(
          publishedSnapshot: publishedSnapshot,
          hasPublishedSnapshot: hasPublishedSnapshot,
          attemptedAccess: attemptedAccess,
          latestStates: latestSnapshot.states,
          generation: generation
        )
        guard
          await recoverSubscription(
            from: error,
            attempt: attempt,
            state: &recoveryState,
            continuation: continuation
          )
        else { return }
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

  private func validateObservation(
    _ access: HomeAssistantWebSocketAccess,
    identity: HomeAssistantObservationIdentity
  ) throws {
    guard access.observationIdentity == identity else {
      throw HomeAssistantAPIError.staleOperation
    }
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
    generation initialGeneration: UUID,
    previousStates: [HomeAssistantState],
    previousRemovals: [String: Date],
    publish: ([HomeAssistantState], [String: Date], UUID) async throws -> Void
  ) async throws {
    let connection = connector.connect(to: access.url)
    try await withTaskCancellationHandler {
      defer {
        connection.cancel()
      }
      try await authenticate(connection, accessToken: access.accessToken)
      try await subscribeToHomeAssistantEvents(over: connection)
      try await session.rememberSuccessfulWebSocketAccess(access)
      var snapshot = try Self.mergedSnapshot(
        try await apiClient.loadHomeAssistantStates(),
        previousStates: previousStates,
        previousRemovals: previousRemovals
      )
      var generation = initialGeneration
      try await session.validateWebSocketAccess(access)
      try await publish(snapshot.orderedStates, snapshot.removals, generation)

      while !Task.isCancelled {
        let data = try await connection.receive()
        let event = try decode(HomeAssistantEventMessage.self, from: data)
        guard
          event.type == "event",
          let subscribedEventType = Self.eventTypeBySubscriptionID[event.id],
          event.event.eventType == subscribedEventType
        else {
          throw HomeAssistantAPIError.invalidResponse
        }
        if subscribedEventType == "state_changed" {
          let stateChange = try decode(HomeAssistantStateChangedMessage.self, from: data)
          try Self.apply(stateChange.event.data, to: &snapshot)
          try await publish(snapshot.orderedStates, snapshot.removals, generation)
        } else {
          generation = UUID()
          try await publish(snapshot.orderedStates, snapshot.removals, generation)
        }
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

  private func subscribeToHomeAssistantEvents(
    over connection: any HomeAssistantWebSocketConnection
  ) async throws {
    for subscription in Self.eventTypeBySubscriptionID.sorted(by: { $0.key < $1.key }) {
      try await send(
        HomeAssistantEventSubscription(
          id: subscription.key,
          type: "subscribe_events",
          eventType: subscription.value
        ),
        over: connection
      )
      let response = try decode(
        HomeAssistantSubscriptionResult.self,
        from: try await connection.receive()
      )
      guard
        response.id == subscription.key,
        response.type == "result",
        response.success
      else {
        throw HomeAssistantAPIError.invalidResponse
      }
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
  fileprivate static let eventTypeBySubscriptionID: [Int: String] = [
    1: "state_changed",
    2: "entity_registry_updated",
    3: "device_registry_updated",
    4: "area_registry_updated",
    5: "floor_registry_updated",
    6: "label_registry_updated",
  ]

  static func yield(
    _ update: HomeAssistantStateUpdate,
    to continuation: HomeAssistantBufferedUpdateStream<
      HomeAssistantStateUpdate
    >.Continuation
  ) {
    continuation.yield(update)
  }

  fileprivate static func yieldLive(
    _ states: [HomeAssistantState],
    generation: UUID,
    to continuation: HomeAssistantBufferedUpdateStream<
      HomeAssistantStateUpdate
    >.Continuation
  ) {
    yield(.live(states, generation: generation), to: continuation)
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

private struct HomeAssistantEventSubscription: Encodable {
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

private struct HomeAssistantEventMessage: Decodable {
  let id: Int
  let type: String
  let event: HomeAssistantEvent
}

private struct HomeAssistantEvent: Decodable {
  let eventType: String

  enum CodingKeys: String, CodingKey {
    case eventType = "event_type"
  }
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

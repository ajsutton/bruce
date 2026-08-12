import Foundation

struct HomeAssistantStateStream: HomeAssistantStateLoading {
  let session: HomeAssistantSession
  private let apiClient: HomeAssistantAPIClient
  private let connector: any HomeAssistantWebSocketConnecting
  let retryDelays: [Duration]
  let sleep: @Sendable (Duration) async throws -> Void
  let heartbeatInterval: Duration
  let heartbeatSleep: @Sendable (Duration) async throws -> Void
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
    },
    heartbeatInterval: Duration = .seconds(30),
    heartbeatSleep: @escaping @Sendable (Duration) async throws -> Void = {
      try await Task.sleep(for: $0)
    }
  ) {
    self.session = session
    self.apiClient = apiClient ?? HomeAssistantAPIClient(session: session)
    self.connector = connector
    self.retryDelays = retryDelays
    self.sleep = sleep
    self.heartbeatInterval = heartbeatInterval
    self.heartbeatSleep = heartbeatSleep
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
    var recoveryState = HomeAssistantReconnectState()
    var observation: HomeAssistantStateOrderingCache.Observation?
    var latestSnapshot = HomeAssistantStateOrderingCache.Snapshot()
    var hasPublishedSnapshot = false
    while !Task.isCancelled {
      var attempt = HomeAssistantReconnectAttempt.starting(
        hasPublishedSnapshot: hasPublishedSnapshot,
        latestStates: latestSnapshot.states
      )
      do {
        let activeObservation = try await activeObservation(observation)
        if observation == nil {
          observation = activeObservation
          latestSnapshot = activeObservation.snapshot
        }
        let accesses = try await session.authenticatedWebSocketAccesses()
        let access = try preferredAccess(
          from: accesses,
          avoiding: recoveryState.lastFailedURL
        )
        try validateObservation(access, identity: activeObservation.identity)
        attempt.attemptedAccess = access
        try await subscribe(
          using: access,
          generation: attempt.generation,
          previousStates: latestSnapshot.states,
          previousRemovals: latestSnapshot.removals
        ) { states, removals, eventGeneration in
          (attempt.publishedSnapshot, hasPublishedSnapshot) = (true, true)
          attempt.latestStates = states
          recoveryState.refreshedAfterUnauthorized = false
          latestSnapshot = .init(states: states, removals: removals)
          try await cache(latestSnapshot, for: activeObservation.id, access: access)
          Self.yieldLive(states, generation: eventGeneration, to: continuation)
        }
      } catch is CancellationError {
        continuation.finish()
        return
      } catch {
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

  private func subscribe(
    using access: HomeAssistantWebSocketAccess,
    generation initialGeneration: UUID,
    previousStates: [HomeAssistantState],
    previousRemovals: [String: Date],
    publish: ([HomeAssistantState], [String: Date], UUID) async throws -> Void
  ) async throws {
    let connection = connector.connect(to: access.url)
    let heartbeatMonitor = HomeAssistantHeartbeatMonitor()
    let heartbeat = Task {
      await monitorLiveness(of: connection, monitor: heartbeatMonitor)
    }
    try await withTaskCancellationHandler {
      defer {
        heartbeat.cancel()
        connection.cancel()
      }
      do {
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
          try await receiveUpdate(
            over: connection,
            snapshot: &snapshot,
            generation: &generation,
            publish: publish
          )
        }
        throw CancellationError()
      } catch {
        if let heartbeatFailure = await heartbeatMonitor.failure {
          throw heartbeatFailure
        }
        throw error
      }
    } onCancel: {
      heartbeat.cancel()
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

  private func receiveUpdate(
    over connection: any HomeAssistantWebSocketConnection,
    snapshot: inout HomeAssistantStateStream.Snapshot,
    generation: inout UUID,
    publish: ([HomeAssistantState], [String: Date], UUID) async throws -> Void
  ) async throws {
    let data = try await connection.receive()
    let event = try decode(HomeAssistantEventMessage.self, from: data)
    guard
      event.type == "event",
      let eventType = Self.eventTypeBySubscriptionID[event.id],
      event.event.eventType == eventType
    else { throw HomeAssistantAPIError.invalidResponse }
    if eventType == "state_changed" {
      let stateChange = try decode(HomeAssistantStateChangedMessage.self, from: data)
      try Self.apply(stateChange.event.data, to: &snapshot)
    } else {
      generation = UUID()
    }
    try await publish(snapshot.orderedStates, snapshot.removals, generation)
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
  private func activeObservation(
    _ observation: HomeAssistantStateOrderingCache.Observation?
  ) async throws -> HomeAssistantStateOrderingCache.Observation {
    if let observation {
      return observation
    }
    return try await beginObservation()
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

import Foundation

extension HomeAssistantConnectionSupervisor {
  func runLifecycle(
    id lifecycleID: UUID,
    trigger: HomeAssistantConnectionTrigger
  ) async {
    var nextTrigger = trigger
    while isCurrentLifecycle(lifecycleID), isRunnable, !Task.isCancelled {
      do {
        try await performAttempt(lifecycleID: lifecycleID, trigger: nextTrigger)
        return
      } catch is CancellationError {
        return
      } catch HomeAssistantAPIError.unauthorized {
        guard await refreshAfterAuthenticationRejection(lifecycleID: lifecycleID) else {
          return
        }
        nextTrigger = .authentication
      } catch {
        guard
          await recover(
            from: error,
            lifecycleID: lifecycleID,
            trigger: .transportClose
          )
        else { return }
        nextTrigger = .transportClose
      }
    }
  }

  private func performAttempt(
    lifecycleID: UUID,
    trigger: HomeAssistantConnectionTrigger
  ) async throws {
    let context = try await openAttempt(lifecycleID: lifecycleID, trigger: trigger)
    try await withTaskCancellationHandler {
      defer {
        context.connection.cancel()
        Task { await context.attempt.finish() }
      }
      let receiver = makeReceiver(
        connection: context.connection,
        attempt: context.attempt
      )
      defer { receiver.cancel() }
      var synchronized = try await synchronize(
        context,
        lifecycleID: lifecycleID
      )
      let heartbeat = makeHeartbeat(
        connection: context.connection,
        attempt: context.attempt,
        lifecycleID: lifecycleID,
        attemptID: context.id
      )
      defer { heartbeat.cancel() }
      startStabilityTimer(lifecycleID: lifecycleID, attemptID: context.id)
      try await consumeEvents(
        &synchronized,
        context: context,
        lifecycleID: lifecycleID
      )
    } onCancel: {
      context.connection.cancel()
      Task { await context.attempt.finish() }
    }
  }

  private func openAttempt(
    lifecycleID: UUID,
    trigger: HomeAssistantConnectionTrigger
  ) async throws -> HomeAssistantAttemptContext {
    let attemptStartedAt = clock.now()
    let accesses = try await session.authenticatedWebSocketAccesses()
    let access = try preferredAccess(from: accesses)
    try validateCurrent(lifecycleID: lifecycleID, access: access)
    acceleratedReplacementPending = false
    transition(to: .connecting, trigger: trigger)

    let connection = connector.connect(to: access.url)
    currentConnection = connection
    currentAccess = access
    let attemptID = UUID()
    let attempt = HomeAssistantConnectionAttempt(
      id: attemptID,
      authenticationSessionEpoch: access.authenticationSessionEpoch,
      routeCategory: routeCategory(for: access, among: accesses),
      now: clock.now
    )
    currentAttempt = attempt
    transition(to: .authenticating, trigger: .authentication)
    do {
      try await authenticate(
        connection,
        access: access,
        connectionStartedAt: attemptStartedAt
      )
      try validateCurrent(lifecycleID: lifecycleID, access: access, attemptID: attemptID)
    } catch {
      connection.cancel()
      await attempt.finish(throwing: error)
      throw error
    }
    return HomeAssistantAttemptContext(
      id: attemptID,
      startedAt: attemptStartedAt,
      access: access,
      connection: connection,
      attempt: attempt
    )
  }

  private func synchronize(
    _ context: HomeAssistantAttemptContext,
    lifecycleID: UUID
  ) async throws -> HomeAssistantSynchronizedAttempt {
    transition(to: .synchronizing, trigger: .authentication)
    let subscriptionStartedAt = clock.now()
    let subscriptions = try await registerSubscriptions(
      connection: context.connection,
      attempt: context.attempt
    )
    logMilestone("subscribe", startedAt: subscriptionStartedAt)
    try await session.rememberSuccessfulWebSocketAccess(context.access)
    try validateCurrent(
      lifecycleID: lifecycleID,
      access: context.access,
      attemptID: context.id
    )
    let synchronizationStartedAt = clock.now()
    let loadedStates = try await loadSnapshot(for: context)
    var snapshot = try HomeAssistantStateReconciler.mergedSnapshot(
      loadedStates,
      previousStates: latestSnapshot.orderedStates,
      previousRemovals: latestSnapshot.removals
    )
    try validateCurrent(
      lifecycleID: lifecycleID,
      access: context.access,
      attemptID: context.id
    )
    let events = try await context.attempt.beginPublishingEvents()
    // A replacement state snapshot cannot reconstruct registry or configuration changes that
    // happened while the previous transport was unavailable. Rotate once after a real data gap
    // so feature projections refresh that metadata before returning to live.
    var generation = hasReachedLiveForAuthenticationSession ? UUID() : registryGeneration
    for event in events.buffered {
      try apply(
        event,
        subscriptions: subscriptions,
        snapshot: &snapshot,
        generation: &generation
      )
    }
    logMilestone("synchronize", startedAt: synchronizationStartedAt)
    try await publishLive(
      snapshot,
      generation: generation,
      lifecycleID: lifecycleID,
      attemptID: context.id,
      authenticationSessionEpoch: context.access.authenticationSessionEpoch
    )
    logMilestone("becomeLive", startedAt: context.startedAt)
    return HomeAssistantSynchronizedAttempt(
      subscriptions: subscriptions,
      events: events.stream,
      snapshot: snapshot,
      generation: generation
    )
  }

  private func loadSnapshot(
    for context: HomeAssistantAttemptContext
  ) async throws -> [HomeAssistantState] {
    let apiClient = apiClient
    return try await withPhaseDeadline {
      try await apiClient.loadHomeAssistantStates()
    } onTimeout: {
      await context.attempt.finish(throwing: URLError(.timedOut))
      context.connection.cancel()
    }
  }

  private func consumeEvents(
    _ synchronized: inout HomeAssistantSynchronizedAttempt,
    context: HomeAssistantAttemptContext,
    lifecycleID: UUID
  ) async throws {
    for try await event in synchronized.events {
      try Task.checkCancellation()
      try apply(
        event,
        subscriptions: synchronized.subscriptions,
        snapshot: &synchronized.snapshot,
        generation: &synchronized.generation
      )
      try await publishLive(
        synchronized.snapshot,
        generation: synchronized.generation,
        lifecycleID: lifecycleID,
        attemptID: context.id,
        authenticationSessionEpoch: context.access.authenticationSessionEpoch
      )
      lastSuccessfulEventAt = clock.now()
    }
    throw URLError(.networkConnectionLost)
  }

  private func authenticate(
    _ connection: any HomeAssistantWebSocketConnection,
    access: HomeAssistantWebSocketAccess,
    connectionStartedAt: TimeInterval
  ) async throws {
    let requiredData = try await withPhaseDeadline {
      try await connection.receive()
    } onTimeout: {
      connection.cancel()
    }
    let required = try decode(HomeAssistantSubscriptionMessageKind.self, from: requiredData)
    guard required.type == "auth_required" else {
      throw HomeAssistantAPIError.invalidResponse
    }
    logMilestone("connect", startedAt: connectionStartedAt)
    let authenticationStartedAt = clock.now()
    try await send(
      HomeAssistantSubscriptionAuthentication(
        type: "auth",
        accessToken: access.accessToken
      ),
      over: connection
    )
    let responseData = try await withPhaseDeadline {
      try await connection.receive()
    } onTimeout: {
      connection.cancel()
    }
    let response = try decode(HomeAssistantSubscriptionMessageKind.self, from: responseData)
    guard response.type == "auth_ok" else {
      if response.type == "auth_invalid" {
        throw HomeAssistantAPIError.unauthorized
      }
      throw HomeAssistantAPIError.invalidResponse
    }
    logMilestone("authenticate", startedAt: authenticationStartedAt)
  }

  private func registerSubscriptions(
    connection: any HomeAssistantWebSocketConnection,
    attempt: HomeAssistantConnectionAttempt
  ) async throws -> [Int: String] {
    var subscriptions: [Int: String] = [:]
    for eventType in Self.logicalEventTypes {
      let id = try await attempt.allocateCommandID()
      subscriptions[id] = eventType
      try await send(
        HomeAssistantEventSubscription(
          id: id,
          type: "subscribe_events",
          eventType: eventType
        ),
        over: connection
      )
      let responseData = try await withPhaseDeadline {
        try await attempt.response(for: id)
      } onTimeout: {
        await attempt.finish(throwing: URLError(.timedOut))
        connection.cancel()
      }
      let response = try decode(HomeAssistantSubscriptionResult.self, from: responseData)
      guard response.id == id, response.type == "result", response.success else {
        throw HomeAssistantAPIError.invalidResponse
      }
    }
    return subscriptions
  }

  private func makeReceiver(
    connection: any HomeAssistantWebSocketConnection,
    attempt: HomeAssistantConnectionAttempt
  ) -> Task<Void, Never> {
    Task {
      do {
        while !Task.isCancelled {
          try await attempt.receive(try await connection.receive())
        }
      } catch {
        await attempt.finish(throwing: error)
      }
    }
  }

  private func apply(
    _ data: Data,
    subscriptions: [Int: String],
    snapshot: inout HomeAssistantStateReconciler.Snapshot,
    generation: inout UUID
  ) throws {
    let event = try decode(HomeAssistantEventMessage.self, from: data)
    guard
      event.type == "event",
      let eventType = subscriptions[event.id],
      event.event.eventType == eventType
    else { throw HomeAssistantAPIError.invalidResponse }
    if eventType == "state_changed" {
      let change = try decode(HomeAssistantStateChangedMessage.self, from: data)
      try HomeAssistantStateReconciler.apply(change.event.data, to: &snapshot)
    } else {
      generation = UUID()
    }
  }

  private func publishLive(
    _ snapshot: HomeAssistantStateReconciler.Snapshot,
    generation: UUID,
    lifecycleID: UUID,
    attemptID: UUID,
    authenticationSessionEpoch: Int
  ) async throws {
    let sessionSnapshot = await session.connectionSnapshot()
    guard
      isCurrent(
        lifecycleID: lifecycleID,
        attemptID: attemptID,
        authenticationSessionEpoch: authenticationSessionEpoch
      ),
      sessionSnapshot.authenticationSessionEpoch == authenticationSessionEpoch
    else { throw HomeAssistantAPIError.staleOperation }
    latestSnapshot = snapshot
    registryGeneration = generation
    let update = Update.live(snapshot.orderedStates, generation: generation)
    latestUpdate = update
    continuations.values.forEach { $0.yield(update) }
    if state != .live {
      terminallyFailedURLs = []
      hasReachedLiveForAuthenticationSession = true
      liveSequence += 1
      transition(to: .live, trigger: .authentication)
      resolveReadinessWaiters()
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

  private func preferredAccess(
    from accesses: [HomeAssistantWebSocketAccess]
  ) throws -> HomeAssistantWebSocketAccess {
    guard !accesses.isEmpty else { throw HomeAssistantAPIError.invalidServerURL }
    return accesses.first {
      $0.baseURL != lastFailedURL && !terminallyFailedURLs.contains($0.baseURL)
    } ?? accesses.first { !terminallyFailedURLs.contains($0.baseURL) } ?? accesses[0]
  }

  private func routeCategory(
    for access: HomeAssistantWebSocketAccess,
    among accesses: [HomeAssistantWebSocketAccess]
  ) -> String {
    access.baseURL == accesses.first?.baseURL ? "preferred" : "alternate"
  }

  private func validateCurrent(
    lifecycleID: UUID,
    access: HomeAssistantWebSocketAccess,
    attemptID: UUID? = nil
  ) throws {
    guard isCurrentLifecycle(lifecycleID), isRunnable else {
      throw CancellationError()
    }
    guard
      credentialSnapshot?.authenticationSessionEpoch == access.authenticationSessionEpoch
    else { throw HomeAssistantAPIError.staleOperation }
    if let attemptID {
      guard currentAttempt?.id == attemptID else {
        throw HomeAssistantAPIError.staleOperation
      }
    }
  }

}

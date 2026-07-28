import Foundation

struct HomeAssistantTemperatureStream: HomeAssistantTemperatureLoading {
  let providesContinuousTemperatureUpdates = true

  private let states: any HomeAssistantStateLoading
  private let apiClient: HomeAssistantAPIClient
  private let contextRetryDelays: [Duration]
  private let sleep: @Sendable (Duration) async throws -> Void

  init(
    states: any HomeAssistantStateLoading,
    apiClient: HomeAssistantAPIClient,
    contextRetryDelays: [Duration] = [
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
    self.states = states
    self.apiClient = apiClient
    self.contextRetryDelays = contextRetryDelays
    self.sleep = sleep
  }

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
    let apiClient = apiClient ?? HomeAssistantAPIClient(session: session)
    states = HomeAssistantStateStream(
      session: session,
      apiClient: apiClient,
      connector: connector,
      retryDelays: retryDelays,
      sleep: sleep
    )
    self.apiClient = apiClient
    contextRetryDelays = retryDelays
    self.sleep = sleep
  }

  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task {
        await produceUpdates(continuation: continuation)
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func produceUpdates(
    continuation: AsyncThrowingStream<
      HomeAssistantTemperatureUpdate, any Error
    >.Continuation
  ) async {
    let producer = HomeAssistantTemperatureUpdateProducer(
      continuation: continuation,
      loadContext: loadTemperatureContextWithRetry
    )
    do {
      for try await stateUpdate in await states.stateUpdates() {
        try Task.checkCancellation()
        await producer.receive(stateUpdate)
      }
      await producer.finish()
    } catch is CancellationError {
      await producer.finish()
    } catch {
      await producer.finish(throwing: error)
    }
  }

  private func loadTemperatureContextWithRetry() async throws
    -> HomeAssistantTemperatureContext
  {
    var retryIndex = 0
    while true {
      do {
        return try await apiClient.loadTemperatureContext()
      } catch {
        guard Self.shouldRetryContextLoad(after: error),
          !contextRetryDelays.isEmpty
        else {
          throw error
        }
        let delay = contextRetryDelays[
          min(retryIndex, contextRetryDelays.count - 1)
        ]
        retryIndex = min(retryIndex + 1, contextRetryDelays.count - 1)
        try await sleep(delay)
      }
    }
  }

  fileprivate static func temperatureUpdate(
    from update: HomeAssistantStateUpdate,
    context: HomeAssistantTemperatureContext
  ) -> HomeAssistantTemperatureUpdate {
    let readings = HomeAssistantAPIClient.temperatureReadings(
      from: update.states,
      context: context
    )
    switch update.phase {
    case .live:
      return .live(readings)
    case .refreshing:
      return .refreshing(readings)
    case .reconnecting:
      return .reconnecting(readings)
    }
  }

  private static func shouldRetryContextLoad(after error: any Error) -> Bool {
    if HomeAssistantRequestRouter.isConnectivityFailure(error) {
      return true
    }
    guard let apiError = error as? HomeAssistantAPIError else {
      return false
    }
    if case .server = apiError {
      return true
    }
    return false
  }
}

private actor HomeAssistantTemperatureUpdateProducer {
  typealias StateUpdate = HomeAssistantStateUpdate
  typealias Continuation = AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  >.Continuation

  private let continuation: Continuation
  private let loadContext: @Sendable () async throws -> HomeAssistantTemperatureContext
  private var context: HomeAssistantTemperatureContext?
  private var contextSourceGeneration: UUID?
  private var contextTask: Task<Void, Never>?
  private var contextTaskGeneration = UUID()
  private var loadingSourceGeneration: UUID?
  private var latestStateUpdate: StateUpdate?
  private var lastPublishedUpdate: HomeAssistantTemperatureUpdate?
  private var cachedReadings: [HomeAssistantTemperatureReading] = []
  private var isFinished = false

  init(
    continuation: Continuation,
    loadContext: @escaping @Sendable () async throws -> HomeAssistantTemperatureContext
  ) {
    self.continuation = continuation
    self.loadContext = loadContext
  }

  func receive(_ update: StateUpdate) {
    guard !isFinished else { return }
    latestStateUpdate = update
    switch update.phase {
    case .live:
      if contextSourceGeneration != update.generation {
        refreshContext(for: update.generation)
      }
    case .refreshing, .reconnecting:
      cancelContextRefresh()
    }
    publish(update)
  }

  func finish(throwing error: (any Error)? = nil) {
    guard !isFinished else { return }
    isFinished = true
    contextTask?.cancel()
    contextTask = nil
    if let error {
      continuation.finish(throwing: error)
    } else {
      continuation.finish()
    }
  }

  private func refreshContext(for sourceGeneration: UUID) {
    if contextTask != nil, loadingSourceGeneration == sourceGeneration {
      return
    }
    cancelContextRefresh()
    let taskGeneration = UUID()
    contextTaskGeneration = taskGeneration
    loadingSourceGeneration = sourceGeneration
    contextTask = Task { [loadContext] in
      do {
        let context = try await loadContext()
        install(
          context,
          taskGeneration: taskGeneration,
          sourceGeneration: sourceGeneration
        )
      } catch is CancellationError {
      } catch {
        finishContextRefresh(with: error, taskGeneration: taskGeneration)
      }
    }
  }

  private func install(
    _ context: HomeAssistantTemperatureContext,
    taskGeneration: UUID,
    sourceGeneration: UUID
  ) {
    guard contextTaskGeneration == taskGeneration,
      latestStateUpdate?.generation == sourceGeneration,
      !isFinished
    else { return }
    self.context = context
    contextSourceGeneration = sourceGeneration
    contextTask = nil
    loadingSourceGeneration = nil
    if let latestStateUpdate {
      publish(latestStateUpdate)
    }
  }

  private func finishContextRefresh(
    with error: any Error,
    taskGeneration: UUID
  ) {
    guard contextTaskGeneration == taskGeneration, !isFinished else { return }
    contextTask = nil
    loadingSourceGeneration = nil
    finish(throwing: error)
  }

  private func cancelContextRefresh() {
    contextTask?.cancel()
    contextTask = nil
    loadingSourceGeneration = nil
    contextTaskGeneration = UUID()
  }

  private func publish(_ stateUpdate: StateUpdate) {
    guard
      let context,
      contextSourceGeneration == stateUpdate.generation
    else {
      switch stateUpdate.phase {
      case .refreshing:
        yield(.refreshing(cachedReadings))
      case .reconnecting:
        yield(.reconnecting(cachedReadings))
      case .live:
        break
      }
      return
    }
    yield(
      HomeAssistantTemperatureStream.temperatureUpdate(
        from: stateUpdate,
        context: context
      ))
  }

  private func yield(_ update: HomeAssistantTemperatureUpdate) {
    guard update != lastPublishedUpdate else { return }
    switch update {
    case .live(let readings), .refreshing(let readings),
      .reconnecting(let readings):
      cachedReadings = readings
    }
    lastPublishedUpdate = update
    continuation.yield(update)
  }
}

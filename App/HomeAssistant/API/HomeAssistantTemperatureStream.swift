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

  func temperatureUpdates() -> HomeAssistantTemperatureUpdateStream {
    let registration = TemperatureSubscriptionRegistration()
    return HomeAssistantTemperatureUpdateStream(
      waitUntilSubscribed: { try await registration.wait() },
      { continuation in
        let task = Task {
          await produceUpdates(
            continuation: continuation,
            registration: registration
          )
        }
        continuation.onTermination = { _ in
          task.cancel()
        }
      }
    )
  }

  private func produceUpdates(
    continuation: HomeAssistantTemperatureUpdateStream.Continuation,
    registration: TemperatureSubscriptionRegistration
  ) async {
    let producer = HomeAssistantTemperatureUpdateProducer(
      continuation: continuation,
      loadContext: loadTemperatureContextWithRetry
    )
    do {
      let stateUpdates = await states.stateUpdates()
      await registration.markSubscribed()
      defer { stateUpdates.cancel() }
      for try await stateUpdate in stateUpdates {
        try Task.checkCancellation()
        await producer.receive(stateUpdate)
      }
      await producer.finish()
    } catch is CancellationError {
      await registration.finish(throwing: CancellationError())
      await producer.finish()
    } catch {
      await registration.finish(throwing: error)
      await producer.finish(throwing: error)
    }
  }

  private func loadTemperatureContextWithRetry(
    sourceGeneration: UUID
  ) async throws
    -> HomeAssistantTemperatureContext
  {
    var retryIndex = 0
    while true {
      do {
        return try await apiClient.loadTemperatureContext(
          sourceGeneration: sourceGeneration
        )
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
    case .unavailable:
      return .unavailable(readings)
    }
  }

  private static func shouldRetryContextLoad(after error: any Error) -> Bool {
    if HomeAssistantRequestRouter.isConnectivityFailure(error) {
      return true
    }
    guard let apiError = error as? HomeAssistantAPIError else {
      return false
    }
    if case .server(let statusCode) = apiError {
      return statusCode == 429 || statusCode >= 500
    }
    if case .staleOperation = apiError {
      return true
    }
    return false
  }
}

private actor TemperatureSubscriptionRegistration {
  private typealias SubscriptionResult = Result<Void, any Error>

  private var result: SubscriptionResult?
  private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

  func wait() async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if let result {
          continuation.resume(with: result)
        } else if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          waiters[id] = continuation
        }
      }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
  }

  func markSubscribed() {
    finish(with: .success(()))
  }

  func finish(throwing error: any Error) {
    finish(with: .failure(error))
  }

  private func finish(with result: SubscriptionResult) {
    guard self.result == nil else { return }
    self.result = result
    let waiters = waiters.values
    self.waiters = [:]
    waiters.forEach { $0.resume(with: result) }
  }

  private func cancelWaiter(_ id: UUID) {
    waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }
}

private actor HomeAssistantTemperatureUpdateProducer {
  typealias StateUpdate = HomeAssistantStateUpdate
  typealias Continuation = HomeAssistantTemperatureUpdateStream.Continuation

  private let continuation: Continuation
  private let loadContext: @Sendable (UUID) async throws -> HomeAssistantTemperatureContext
  private var context: HomeAssistantTemperatureContext?
  private var contextSourceGeneration: UUID?
  private var contextTask: Task<Void, Never>?
  private var contextTaskGeneration = UUID()
  private var loadingSourceGeneration: UUID?
  private var terminallyFailedSourceGeneration: UUID?
  private var latestStateUpdate: StateUpdate?
  private var lastPublishedUpdate: HomeAssistantTemperatureUpdate?
  private var cachedReadings: [HomeAssistantTemperatureReading] = []
  private var isFinished = false

  init(
    continuation: Continuation,
    loadContext:
      @escaping @Sendable (UUID) async throws
      -> HomeAssistantTemperatureContext
  ) {
    self.continuation = continuation
    self.loadContext = loadContext
  }

  func receive(_ update: StateUpdate) {
    guard !isFinished else { return }
    latestStateUpdate = update
    switch update.phase {
    case .live:
      if contextSourceGeneration != update.generation,
        terminallyFailedSourceGeneration != update.generation
      {
        if contextSourceGeneration != nil || !cachedReadings.isEmpty {
          yield(.refreshing(cachedReadings))
        }
        refreshContext(for: update.generation)
      }
    case .refreshing, .reconnecting, .unavailable:
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
        let context = try await loadContext(sourceGeneration)
        install(
          context,
          taskGeneration: taskGeneration,
          sourceGeneration: sourceGeneration
        )
      } catch is CancellationError {
      } catch {
        finishContextRefresh(
          with: error,
          taskGeneration: taskGeneration,
          sourceGeneration: sourceGeneration
        )
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
    terminallyFailedSourceGeneration = nil
    contextTask = nil
    loadingSourceGeneration = nil
    if let latestStateUpdate {
      publish(latestStateUpdate)
    }
  }

  private func finishContextRefresh(
    with _: any Error,
    taskGeneration: UUID,
    sourceGeneration: UUID
  ) {
    guard contextTaskGeneration == taskGeneration, !isFinished else { return }
    contextTask = nil
    terminallyFailedSourceGeneration = sourceGeneration
    loadingSourceGeneration = nil
    yield(.unavailable(cachedReadings))
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
      case .unavailable:
        yield(.unavailable(cachedReadings))
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
      .reconnecting(let readings), .unavailable(let readings):
      cachedReadings = readings
    }
    lastPublishedUpdate = update
    continuation.yield(update)
  }
}

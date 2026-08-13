import Foundation

struct HomeAssistantGarageDoorStream: HomeAssistantGarageDoorLoading {
  let providesContinuousUpdates = true

  private let states: any HomeAssistantStateLoading
  private let registryLoader: any HomeAssistantGarageDoorRegistryLoading
  private let retryDelays: [Duration]
  private let sleep: @Sendable (Duration) async throws -> Void

  init(
    states: any HomeAssistantStateLoading,
    registryLoader: any HomeAssistantGarageDoorRegistryLoading,
    retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(10)],
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.states = states
    self.registryLoader = registryLoader
    self.retryDelays = retryDelays
    self.sleep = sleep
  }

  func garageDoorUpdates() -> HomeAssistantGarageDoorUpdateStream {
    HomeAssistantGarageDoorUpdateStream { continuation in
      let task = Task {
        await produceUpdates(continuation: continuation)
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] {
    for try await update in garageDoorUpdates() {
      if case .live(let doors) = update {
        return doors
      }
    }
    throw HomeAssistantAPIError.invalidResponse
  }

  private func produceUpdates(
    continuation: HomeAssistantGarageDoorUpdateStream.Continuation
  ) async {
    let producer = HomeAssistantGarageDoorUpdateProducer(
      continuation: continuation,
      loadRegistry: loadRegistryWithRetry
    )
    do {
      let stateUpdates = await states.stateUpdates()
      defer { stateUpdates.cancel() }
      for try await stateUpdate in stateUpdates {
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

  private func loadRegistryWithRetry() async throws -> HomeAssistantGarageDoorRegistry {
    var retry = 0
    while true {
      do {
        return try await registryLoader.loadGarageDoorRegistry()
      } catch {
        guard Self.isRecoverable(error), !retryDelays.isEmpty else { throw error }
        try await sleep(retryDelays[min(retry, retryDelays.count - 1)])
        retry = min(retry + 1, retryDelays.count - 1)
      }
    }
  }

  private static func isRecoverable(_ error: any Error) -> Bool {
    if HomeAssistantRequestRouter.isConnectivityFailure(error) { return true }
    guard let error = error as? HomeAssistantAPIError else { return false }
    return switch error {
    case .server(let statusCode): statusCode == 429 || statusCode >= 500
    case .staleOperation: true
    case .noCredentials, .invalidServerURL, .invalidResponse, .unauthorized,
      .reauthenticationRequired, .incompatibleServer:
      false
    }
  }
}

private actor HomeAssistantGarageDoorUpdateProducer {
  typealias Continuation = HomeAssistantGarageDoorUpdateStream.Continuation

  private let continuation: Continuation
  private let loadRegistry: @Sendable () async throws -> HomeAssistantGarageDoorRegistry
  private var registry: HomeAssistantGarageDoorRegistry?
  private var registrySourceGeneration: UUID?
  private var registryTask: Task<Void, Never>?
  private var registryTaskGeneration = UUID()
  private var loadingSourceGeneration: UUID?
  private var terminallyFailedSourceGeneration: UUID?
  private var latestStateUpdate: HomeAssistantStateUpdate?
  private var lastPublishedUpdate: HomeAssistantGarageDoorUpdate?
  private var cachedDoors: [HomeAssistantGarageDoorSnapshot] = []
  private var isFinished = false

  init(
    continuation: Continuation,
    loadRegistry: @escaping @Sendable () async throws -> HomeAssistantGarageDoorRegistry
  ) {
    self.continuation = continuation
    self.loadRegistry = loadRegistry
  }

  func receive(_ update: HomeAssistantStateUpdate) {
    guard !isFinished else { return }
    latestStateUpdate = update
    switch update.phase {
    case .live:
      if registrySourceGeneration != update.generation,
        terminallyFailedSourceGeneration != update.generation
      {
        refreshRegistry(for: update.generation)
      }
    case .refreshing, .reconnecting, .unavailable:
      cancelRegistryRefresh()
    }
    publish(update)
  }

  func finish(throwing error: (any Error)? = nil) {
    guard !isFinished else { return }
    isFinished = true
    registryTask?.cancel()
    registryTask = nil
    if let error {
      continuation.finish(throwing: error)
    } else {
      continuation.finish()
    }
  }

  private func refreshRegistry(for sourceGeneration: UUID) {
    if registryTask != nil, loadingSourceGeneration == sourceGeneration {
      return
    }
    cancelRegistryRefresh()
    let taskGeneration = UUID()
    registryTaskGeneration = taskGeneration
    loadingSourceGeneration = sourceGeneration
    registryTask = Task { [loadRegistry] in
      do {
        let registry = try await loadRegistry()
        install(
          registry,
          taskGeneration: taskGeneration,
          sourceGeneration: sourceGeneration
        )
      } catch is CancellationError {
      } catch {
        finishRegistryRefresh(
          with: error,
          taskGeneration: taskGeneration,
          sourceGeneration: sourceGeneration
        )
      }
    }
  }

  private func install(
    _ registry: HomeAssistantGarageDoorRegistry,
    taskGeneration: UUID,
    sourceGeneration: UUID
  ) {
    guard registryTaskGeneration == taskGeneration,
      latestStateUpdate?.generation == sourceGeneration,
      latestStateUpdate?.phase == .live,
      !isFinished
    else { return }
    self.registry = registry
    registrySourceGeneration = sourceGeneration
    terminallyFailedSourceGeneration = nil
    registryTask = nil
    loadingSourceGeneration = nil
    if let latestStateUpdate {
      publish(latestStateUpdate)
    }
  }

  private func finishRegistryRefresh(
    with _: any Error,
    taskGeneration: UUID,
    sourceGeneration: UUID
  ) {
    guard registryTaskGeneration == taskGeneration, !isFinished else { return }
    registryTask = nil
    terminallyFailedSourceGeneration = sourceGeneration
    loadingSourceGeneration = nil
    yield(.unavailable(cachedDoors))
  }

  private func cancelRegistryRefresh() {
    registryTask?.cancel()
    registryTask = nil
    loadingSourceGeneration = nil
    registryTaskGeneration = UUID()
  }

  private func publish(_ stateUpdate: HomeAssistantStateUpdate) {
    guard
      let registry,
      registrySourceGeneration == stateUpdate.generation
    else {
      publishCachedDoors(for: stateUpdate.phase)
      return
    }
    let doors = HomeAssistantGarageDoorSnapshot.snapshots(
      states: stateUpdate.states,
      registry: registry
    )
    yield(update(doors: doors, phase: stateUpdate.phase))
  }

  private func publishCachedDoors(for phase: HomeAssistantStateUpdate.Phase) {
    switch phase {
    case .live:
      break
    case .refreshing:
      yield(.refreshing(cachedDoors))
    case .reconnecting:
      yield(.reconnecting(cachedDoors))
    case .unavailable:
      yield(.unavailable(cachedDoors))
    }
  }

  private func update(
    doors: [HomeAssistantGarageDoorSnapshot],
    phase: HomeAssistantStateUpdate.Phase
  ) -> HomeAssistantGarageDoorUpdate {
    switch phase {
    case .live: .live(doors)
    case .refreshing: .refreshing(doors)
    case .reconnecting: .reconnecting(doors)
    case .unavailable: .unavailable(doors)
    }
  }

  private func yield(_ update: HomeAssistantGarageDoorUpdate) {
    guard update != lastPublishedUpdate else { return }
    switch update {
    case .live(let doors), .refreshing(let doors), .reconnecting(let doors),
      .unavailable(let doors):
      cachedDoors = doors
    }
    lastPublishedUpdate = update
    continuation.yield(update)
  }
}

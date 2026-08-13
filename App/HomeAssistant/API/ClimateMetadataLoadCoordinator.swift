import Foundation

final class ClimateMetadataLoadCoordinator: @unchecked Sendable {
  typealias Output = [String: HomeAssistantClimateMetadata]

  private typealias LoadResult = Result<Output, any Error>

  private enum Generation: Hashable {
    case unscoped
    case source(UUID)
  }

  private struct ActiveLoad {
    let id: UUID
    let task: Task<Void, Never>
  }

  private struct GenerationState {
    var activeLoad: ActiveLoad?
    var waiters: [UUID: ClimateMetadataLoadWaiter] = [:]
    var cachedOutput: Output?
  }

  private struct Registration {
    let abandonedLoads: [Task<Void, Never>]
    let abandonedWaiters: [ClimateMetadataLoadWaiter]
  }

  private let lock = NSLock()
  private var states: [Generation: GenerationState] = [:]
  private var latestSourceGeneration: UUID?

  func load(
    sourceGeneration: UUID? = nil,
    timeout: Duration,
    operation: @escaping @Sendable () async throws -> Output
  ) async throws -> Output {
    let generation = sourceGeneration.map(Generation.source) ?? .unscoped
    let waiter = ClimateMetadataLoadWaiter()
    let registration = register(
      waiter,
      generation: generation,
      timeout: timeout,
      operation: operation
    )
    registration.abandonedLoads.forEach { $0.cancel() }
    registration.abandonedWaiters.forEach {
      $0.resolve(.failure(CancellationError()))
    }
    let result = await withTaskCancellationHandler {
      await waiter.result()
    } onCancel: {
      complete(
        waiter,
        generation: generation,
        with: .failure(CancellationError())
      )
    }
    return try result.get()
  }

  private func register(
    _ waiter: ClimateMetadataLoadWaiter,
    generation: Generation,
    timeout: Duration,
    operation: @escaping @Sendable () async throws -> Output
  ) -> Registration {
    let registration = lock.withLock {
      let registration = abandonObsoleteLoads(for: generation)

      var state = states[generation] ?? GenerationState()
      state.waiters[waiter.id] = waiter
      if state.activeLoad == nil {
        let loadID = UUID()
        let task = Task { [weak self] in
          do {
            self?.finish(
              generation: generation,
              loadID: loadID,
              with: .success(try await operation())
            )
          } catch {
            self?.finish(
              generation: generation,
              loadID: loadID,
              with: .failure(error)
            )
          }
        }
        state.activeLoad = ActiveLoad(id: loadID, task: task)
      }
      states[generation] = state
      return Registration(
        abandonedLoads: registration.abandonedLoads,
        abandonedWaiters: registration.abandonedWaiters
      )
    }
    waiter.startTimeout(after: timeout) { [weak self, weak waiter] in
      guard let self, let waiter else { return }
      complete(
        waiter,
        generation: generation,
        with: timeoutResult(for: generation)
      )
    }
    return registration
  }

  private func abandonObsoleteLoads(for generation: Generation) -> Registration {
    guard case .source(let sourceGeneration) = generation,
      latestSourceGeneration != sourceGeneration
    else {
      return Registration(abandonedLoads: [], abandonedWaiters: [])
    }
    latestSourceGeneration = sourceGeneration
    let obsoleteGenerations = states.keys.filter {
      if case .source(let existingGeneration) = $0 {
        return existingGeneration != sourceGeneration
      }
      return false
    }
    var abandonedLoads: [Task<Void, Never>] = []
    var abandonedWaiters: [ClimateMetadataLoadWaiter] = []
    for obsoleteGeneration in obsoleteGenerations {
      guard let state = states.removeValue(forKey: obsoleteGeneration) else {
        continue
      }
      if let task = state.activeLoad?.task {
        abandonedLoads.append(task)
      }
      abandonedWaiters.append(contentsOf: state.waiters.values)
    }
    return Registration(
      abandonedLoads: abandonedLoads,
      abandonedWaiters: abandonedWaiters
    )
  }

  private func complete(
    _ waiter: ClimateMetadataLoadWaiter,
    generation: Generation,
    with result: LoadResult
  ) {
    let loadToCancel = lock.withLock {
      guard var state = states[generation],
        state.waiters.removeValue(forKey: waiter.id) != nil
      else {
        return Optional<Task<Void, Never>>.none
      }
      guard state.waiters.isEmpty else {
        states[generation] = state
        return nil
      }
      let load = state.activeLoad?.task
      state.activeLoad = nil
      states[generation] = state
      return load
    }
    loadToCancel?.cancel()
    waiter.resolve(result)
  }

  private func finish(
    generation: Generation,
    loadID: UUID,
    with result: LoadResult
  ) {
    let completion = lock.withLock {
      guard var state = states[generation],
        state.activeLoad?.id == loadID
      else {
        return Optional<([ClimateMetadataLoadWaiter], LoadResult)>.none
      }
      state.activeLoad = nil
      let resolvedResult = resolved(result, cachedOutput: &state.cachedOutput)
      let waiters = Array(state.waiters.values)
      state.waiters.removeAll()
      states[generation] = state
      return (waiters, resolvedResult)
    }
    completion?.0.forEach { $0.resolve(completion?.1 ?? result) }
  }

  private func timeoutResult(for generation: Generation) -> LoadResult {
    lock.withLock {
      states[generation]?.cachedOutput.map(LoadResult.success)
        ?? .failure(URLError(.timedOut))
    }
  }

  private func resolved(
    _ result: LoadResult,
    cachedOutput: inout Output?
  ) -> LoadResult {
    switch result {
    case .success(let output):
      cachedOutput = output
      return result
    case .failure(let error):
      guard Self.canUseCachedOutput(after: error), let cachedOutput else {
        return result
      }
      return .success(cachedOutput)
    }
  }

  private static func canUseCachedOutput(after error: any Error) -> Bool {
    if HomeAssistantRequestRouter.isConnectivityFailure(error) {
      return true
    }
    guard let apiError = error as? HomeAssistantAPIError else { return false }
    if case .server = apiError {
      return true
    }
    return false
  }
}

private final class ClimateMetadataLoadWaiter: @unchecked Sendable {
  typealias LoadResult = Result<[String: HomeAssistantClimateMetadata], any Error>

  let id = UUID()

  private let lock = NSLock()
  private var continuation: CheckedContinuation<LoadResult, Never>?
  private var pendingResult: LoadResult?
  private var timeoutTask: Task<Void, Never>?
  private var isFinished = false

  func result() async -> LoadResult {
    await withCheckedContinuation { continuation in
      let pendingResult = lock.withLock {
        guard let pendingResult = self.pendingResult else {
          self.continuation = continuation
          return Optional<LoadResult>.none
        }
        self.pendingResult = nil
        return pendingResult
      }
      if let pendingResult {
        continuation.resume(returning: pendingResult)
      }
    }
  }

  func startTimeout(
    after timeout: Duration,
    onTimeout: @escaping @Sendable () -> Void
  ) {
    let timeoutTask = Task {
      do {
        try await Task.sleep(for: timeout)
        onTimeout()
      } catch is CancellationError {
      } catch {
        onTimeout()
      }
    }
    let shouldCancel = lock.withLock {
      guard !isFinished else { return true }
      self.timeoutTask = timeoutTask
      return false
    }
    if shouldCancel {
      timeoutTask.cancel()
    }
  }

  func resolve(_ result: LoadResult) {
    let completion = lock.withLock {
      guard !isFinished else {
        return (
          continuation: Optional<CheckedContinuation<LoadResult, Never>>.none,
          timeoutTask: Optional<Task<Void, Never>>.none
        )
      }
      isFinished = true
      let continuation = self.continuation
      if continuation == nil {
        pendingResult = result
      }
      self.continuation = nil
      let timeoutTask = self.timeoutTask
      self.timeoutTask = nil
      return (continuation, timeoutTask)
    }
    completion.timeoutTask?.cancel()
    completion.continuation?.resume(returning: result)
  }
}

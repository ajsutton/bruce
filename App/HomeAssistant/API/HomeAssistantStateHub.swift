import Foundation

actor HomeAssistantStateHub: HomeAssistantStateLoading {
  private typealias Update = HomeAssistantStateUpdate
  private typealias Continuation = AsyncThrowingStream<Update, any Error>.Continuation

  private let source: any HomeAssistantStateLoading
  private var continuations: [UUID: Continuation] = [:]
  private var latestUpdate: Update?
  private var sourceTask: Task<Void, Never>?
  private var sourceGeneration = UUID()

  init(source: any HomeAssistantStateLoading) {
    self.source = source
  }

  func stateUpdates() -> AsyncThrowingStream<
    HomeAssistantStateUpdate, any Error
  > {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let id = UUID()
      add(continuation, id: id)
      continuation.onTermination = { _ in
        Task {
          await self.remove(id: id)
        }
      }
    }
  }

  func refresh() async -> Bool {
    let hasActiveSubscribers = !continuations.isEmpty
    if hasActiveSubscribers, let latestUpdate {
      let refreshingUpdate = refreshingUpdate(from: latestUpdate)
      self.latestUpdate = refreshingUpdate
      continuations.values.forEach {
        $0.yield(refreshingUpdate)
      }
    }
    sourceGeneration = UUID()
    sourceTask?.cancel()
    sourceTask = nil
    if hasActiveSubscribers {
      startSourceIfNeeded()
    }
    return hasActiveSubscribers
  }

  func reset() async {
    sourceGeneration = UUID()
    let task = sourceTask
    sourceTask = nil
    latestUpdate = nil
    task?.cancel()
    await task?.value
  }

  private func add(_ continuation: Continuation, id: UUID) {
    continuations[id] = continuation
    if let latestUpdate {
      continuation.yield(latestUpdate)
    }
    startSourceIfNeeded()
  }

  private func remove(id: UUID) {
    continuations.removeValue(forKey: id)
    guard continuations.isEmpty else { return }
    sourceGeneration = UUID()
    sourceTask?.cancel()
    sourceTask = nil
    latestUpdate = nil
  }

  private func startSourceIfNeeded() {
    guard sourceTask == nil else { return }
    let generation = UUID()
    sourceGeneration = generation
    let source = source
    sourceTask = Task { [weak self] in
      do {
        let updates = await source.stateUpdates()
        for try await update in updates {
          guard !Task.isCancelled else { return }
          await self?.publish(update, generation: generation)
        }
        await self?.finish(with: nil, generation: generation)
      } catch {
        await self?.finish(with: error, generation: generation)
      }
    }
  }

  private func publish(_ update: Update, generation: UUID) {
    guard sourceGeneration == generation else { return }
    let presentedUpdate = presentedUpdate(update)
    latestUpdate = presentedUpdate
    for continuation in continuations.values {
      continuation.yield(presentedUpdate)
    }
  }

  private func presentedUpdate(_ update: Update) -> Update {
    guard update.phase == .reconnecting, update.states.isEmpty,
      let latestUpdate
    else {
      return update
    }
    return .reconnecting(
      latestUpdate.states,
      generation: latestUpdate.generation
    )
  }

  private func refreshingUpdate(from update: Update) -> Update {
    .refreshing(update.states, generation: update.generation)
  }

  private func finish(with error: (any Error)?, generation: UUID) {
    guard sourceGeneration == generation else { return }
    sourceTask = nil
    latestUpdate = nil
    let activeContinuations = continuations.values
    continuations = [:]
    for continuation in activeContinuations {
      if let error {
        continuation.finish(throwing: error)
      } else {
        continuation.finish()
      }
    }
  }
}

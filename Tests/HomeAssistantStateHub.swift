import Foundation

@testable import Bruce

/// Test-only fanout for controlled finite sources. Production connection ownership belongs to
/// `HomeAssistantConnectionSupervisor`.
actor HomeAssistantStateHub: HomeAssistantStateLoading {
  typealias Update = HomeAssistantStateUpdate
  typealias Stream = HomeAssistantBufferedUpdateStream<Update>
  typealias Continuation = Stream.Continuation

  private let source: any HomeAssistantStateLoading
  private var continuations: [UUID: Continuation] = [:]
  private var latestUpdate: Update?
  private var sourceTask: Task<Void, Never>?
  private var sourceGeneration = UUID()

  init(source: any HomeAssistantStateLoading) {
    self.source = source
  }

  func stateUpdates() -> Stream {
    Stream { continuation in
      let id = UUID()
      continuations[id] = continuation
      if let latestUpdate { continuation.yield(latestUpdate) }
      startSourceIfNeeded()
      continuation.onTermination = { _ in
        Task { await self.remove(id: id) }
      }
    }
  }

  func refresh() async -> Bool {
    guard !continuations.isEmpty else { return false }
    if let latestUpdate {
      let refreshing = Update.refreshing(
        latestUpdate.states,
        generation: latestUpdate.generation
      )
      self.latestUpdate = refreshing
      continuations.values.forEach { $0.yield(refreshing) }
    }
    sourceGeneration = UUID()
    sourceTask?.cancel()
    sourceTask = nil
    startSourceIfNeeded()
    return true
  }

  func reset() {
    sourceGeneration = UUID()
    sourceTask?.cancel()
    sourceTask = nil
    latestUpdate = nil
  }

  private func remove(id: UUID) {
    continuations[id] = nil
    guard continuations.isEmpty else { return }
    reset()
  }

  private func startSourceIfNeeded() {
    guard sourceTask == nil else { return }
    let generation = UUID()
    sourceGeneration = generation
    sourceTask = Task {
      do {
        let updates = await source.stateUpdates()
        defer { updates.cancel() }
        for try await update in updates {
          guard !Task.isCancelled else { return }
          publish(update, generation: generation)
        }
        finish(generation: generation)
      } catch {
        finish(error: error, generation: generation)
      }
    }
  }

  private func publish(_ update: Update, generation: UUID) {
    guard sourceGeneration == generation else { return }
    latestUpdate = update
    continuations.values.forEach { $0.yield(update) }
  }

  private func finish(error: (any Error)? = nil, generation: UUID) {
    guard sourceGeneration == generation else { return }
    sourceTask = nil
    latestUpdate = nil
    let active = continuations.values
    continuations = [:]
    active.forEach { $0.finish(throwing: error) }
  }
}

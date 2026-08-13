import Foundation

extension HomeAssistantTemperatureStore {
  func finishObservation(generation: UUID) {
    if activeObservationGeneration == generation {
      activeObservationGeneration = nil
    }
  }

  func requireFreshLiveData(
    from supervisor: HomeAssistantConnectionSupervisor,
    deadline: Duration = .seconds(30)
  ) async throws {
    let baseline = liveSequence
    let requiresControl = await supervisor.state == .live
    var readiness: Task<Void, any Error>?
    await withCheckedContinuation { registered in
      readiness = Task {
        try await waitForLive(
          after: baseline,
          requiresControl: requiresControl,
          deadline: deadline,
          registered: registered
        )
      }
    }
    guard let readiness else { throw CancellationError() }
    let startsTemporaryObservation = activeObservationGeneration == nil
    let updates: HomeAssistantTemperatureUpdateStream?
    if startsTemporaryObservation {
      cancelReadinessLoad()
      let newUpdates = loader.temperatureUpdates()
      updates = newUpdates
      readinessLoadTask = Task { await self.load(updates: newUpdates) }
    } else {
      updates = nil
    }
    do {
      try await updates?.waitUntilSubscribed()
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await supervisor.requireFreshLiveData() }
        group.addTask { try await readiness.value }
        while try await group.next() != nil {}
      }
    } catch {
      readiness.cancel()
      cancelReadinessLoad()
      throw error
    }
  }

  private func waitForLive(
    after baseline: Int,
    requiresControl: Bool,
    deadline: Duration,
    registered: CheckedContinuation<Void, Never>
  ) async throws {
    let id = UUID()
    let timeout = Task {
      try await sleep(deadline)
      self.failLiveWaiter(id, error: URLError(.timedOut))
    }
    defer { timeout.cancel() }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        liveWaiters[id] = LiveWaiter(
          baseline: baseline,
          requiresControl: requiresControl,
          continuation: $0
        )
        registered.resume()
      }
    } onCancel: {
      Task { @MainActor in self.failLiveWaiter(id, error: CancellationError()) }
    }
  }

  private func failLiveWaiter(_ id: UUID, error: any Error) {
    liveWaiters.removeValue(forKey: id)?.continuation.resume(throwing: error)
  }
}

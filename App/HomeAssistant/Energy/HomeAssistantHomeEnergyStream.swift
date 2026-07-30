struct HomeAssistantHomeEnergyStream: HomeAssistantHomeEnergyLoading {
  let providesContinuousEnergyUpdates = true

  private let states: any HomeAssistantStateLoading
  private let loader: any HomeAssistantHomeEnergyLoading

  init(
    states: any HomeAssistantStateLoading,
    loader: any HomeAssistantHomeEnergyLoading
  ) {
    self.states = states
    self.loader = loader
  }

  func homeEnergyUpdates() -> AsyncThrowingStream<
    HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>, any Error
  > {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task {
        do {
          let stateUpdates = await states.stateUpdates()
          for try await stateUpdate in stateUpdates {
            try Task.checkCancellation()
            let update = Self.homeEnergyUpdate(from: stateUpdate)
            Self.yield(update, to: continuation)
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    try await loader.loadHomeEnergySnapshot()
  }

  func loadHomeEnergyBatteryHistory() async throws -> HomeEnergyBatteryHistory {
    try await loader.loadHomeEnergyBatteryHistory()
  }

  func loadHomeEnergyPriceHistory() async throws -> HomeEnergyPriceHistory {
    try await loader.loadHomeEnergyPriceHistory()
  }

  private static func homeEnergyUpdate(
    from update: HomeAssistantStateUpdate
  ) -> HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot> {
    var snapshot = HomeAssistantHomeEnergySnapshot(states: update.states)
    if update.requiresHistoryBackfill {
      snapshot = snapshot.requiringHistoryBackfill()
    }
    return switch update.phase {
    case .live:
      .live(snapshot)
    case .refreshing:
      .refreshing(snapshot)
    case .reconnecting:
      .reconnecting(snapshot)
    }
  }

  static func yield(
    _ update: HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>,
    to continuation: AsyncThrowingStream<
      HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>, any Error
    >.Continuation
  ) {
    if case .dropped = continuation.yield(update) {
      continuation.yield(update.requiringHistoryBackfill())
    }
  }
}

extension HomeAssistantLiveUpdate
where Value == HomeAssistantHomeEnergySnapshot {
  fileprivate func requiringHistoryBackfill() -> Self {
    switch self {
    case .live(let snapshot):
      .live(snapshot.requiringHistoryBackfill())
    case .refreshing(let snapshot):
      .refreshing(snapshot.requiringHistoryBackfill())
    case .reconnecting(let snapshot):
      .reconnecting(snapshot.requiringHistoryBackfill())
    }
  }
}

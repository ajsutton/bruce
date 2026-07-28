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
          var lastUpdate: HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>?
          let stateUpdates = await states.stateUpdates()
          for try await stateUpdate in stateUpdates {
            try Task.checkCancellation()
            let update = Self.homeEnergyUpdate(from: stateUpdate)
            guard update != lastUpdate else { continue }
            lastUpdate = update
            continuation.yield(update)
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

  private static func homeEnergyUpdate(
    from update: HomeAssistantStateUpdate
  ) -> HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot> {
    switch update.phase {
    case .live:
      .live(HomeAssistantHomeEnergySnapshot(states: update.states))
    case .refreshing:
      .refreshing(HomeAssistantHomeEnergySnapshot(states: update.states))
    case .reconnecting:
      .reconnecting(HomeAssistantHomeEnergySnapshot(states: update.states))
    }
  }
}

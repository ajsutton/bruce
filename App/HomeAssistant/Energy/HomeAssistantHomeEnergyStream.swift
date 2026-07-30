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

  func homeEnergyUpdates() -> HomeAssistantHomeEnergyUpdateStream {
    HomeAssistantHomeEnergyUpdateStream { continuation in
      let task = Task {
        do {
          let stateUpdates = await states.stateUpdates()
          defer { stateUpdates.cancel() }
          for try await stateUpdate in stateUpdates {
            try Task.checkCancellation()
            let update = Self.homeEnergyUpdate(from: stateUpdate)
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

  func loadHomeEnergyFlowHistory() async throws -> HomeEnergyFlowHistory {
    try await loader.loadHomeEnergyFlowHistory()
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
    let snapshot = HomeAssistantHomeEnergySnapshot(states: update.states)
    return switch update.phase {
    case .live:
      .live(snapshot)
    case .refreshing:
      .refreshing(snapshot)
    case .reconnecting:
      .reconnecting(snapshot)
    }
  }

}

extension HomeAssistantLiveUpdate {
  func preservingControlTransition(from dropped: Self) -> Self? {
    guard case .live(let latestValue) = self else { return nil }
    return switch dropped {
    case .live:
      nil
    case .refreshing:
      .refreshing(latestValue)
    case .reconnecting:
      .reconnecting(latestValue)
    }
  }

  func preservingLiveTransition(from dropped: Self) -> Self? {
    guard
      case .live(let latestValue) = self,
      case .live(let previousValue) = dropped,
      let latestSnapshot = latestValue as? HomeAssistantHomeEnergySnapshot,
      let previousSnapshot = previousValue as? HomeAssistantHomeEnergySnapshot,
      latestSnapshot.hasAvailabilityTransition(from: previousSnapshot)
    else {
      return nil
    }
    return dropped
  }
}

extension HomeAssistantLiveUpdate: HomeAssistantBufferedUpdate {
  var isLiveUpdate: Bool {
    if case .live = self {
      true
    } else {
      false
    }
  }
}

import Foundation

struct HomeAssistantHomeEnergyStream: HomeAssistantHomeEnergyLoading {
  let providesContinuousEnergyUpdates = true

  private let states: any HomeAssistantStateLoading
  private let loader: any HomeAssistantHomeEnergyLoading
  private let dailyTotalsLoader: (any HomeAssistantDailyEnergyTotalsLoading)?
  private let now: @Sendable () -> Date
  private let dailyRefreshSleep: @Sendable (Date) async throws -> Void
  private let dailyRequestTimeout: Duration

  init(
    states: any HomeAssistantStateLoading,
    loader: any HomeAssistantHomeEnergyLoading,
    dailyTotalsLoader: (any HomeAssistantDailyEnergyTotalsLoading)? = nil,
    now: @escaping @Sendable () -> Date = Date.init,
    dailyRefreshSleep: (@Sendable (Date) async throws -> Void)? = nil,
    dailyRequestTimeout: Duration = .seconds(15)
  ) {
    self.states = states
    self.loader = loader
    self.dailyTotalsLoader = dailyTotalsLoader
    self.now = now
    self.dailyRefreshSleep =
      dailyRefreshSleep
      ?? { deadline in
        let delay = max(deadline.timeIntervalSince(now()), 0)
        try await Task.sleep(for: .seconds(delay))
      }
    self.dailyRequestTimeout = dailyRequestTimeout
  }

  func homeEnergyUpdates() -> HomeAssistantHomeEnergyUpdateStream {
    HomeAssistantHomeEnergyUpdateStream { continuation in
      let task = Task {
        let stateUpdates = await states.stateUpdates()
        let coordinator = DailyEnergyStreamCoordinator(
          loader: dailyTotalsLoader,
          now: now,
          sleepUntil: dailyRefreshSleep,
          requestTimeout: dailyRequestTimeout,
          yield: { continuation.yield($0) },
          finish: { continuation.finish(throwing: $0) },
          cancelStates: { stateUpdates.cancel() }
        )
        do {
          for try await stateUpdate in stateUpdates {
            try Task.checkCancellation()
            await coordinator.handle(stateUpdate)
          }
          await coordinator.finish()
        } catch is CancellationError {
          await coordinator.finish()
        } catch {
          await coordinator.finish(throwing: error)
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
    case .unavailable:
      .unavailable(latestValue)
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

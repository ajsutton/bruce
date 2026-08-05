import Foundation

enum HomeEnergyHistorySampling {
  static let interval: TimeInterval = 2 * 60
}

extension HomeAssistantHomeEnergyStore {
  var hasUsableHistory: Bool {
    flowHistoryStore.hasUsableHistory
      && batteryHistoryStore.hasUsableHistory
      && priceHistoryStore.hasUsableHistory
  }

  var hasCurrentHistory: Bool {
    hasUsableHistory
      && !flowHistoryStore.isStale
      && !batteryHistoryStore.isStale
      && !priceHistoryStore.isStale
      && !flowHistoryStore.isLoading
      && !batteryHistoryStore.isLoading
      && !priceHistoryStore.isLoading
  }

  func reloadHistory() {
    flowHistoryStore.reload()
    batteryHistoryStore.reload()
    priceHistoryStore.reload()
  }

  func recordHistory(
    snapshot: HomeAssistantHomeEnergySnapshot,
    at timestamp: Date
  ) {
    flowHistoryStore.record(snapshot: snapshot, at: timestamp)
    batteryHistoryStore.record(snapshot: snapshot, at: timestamp)
    priceHistoryStore.record(snapshot: snapshot, at: timestamp)
  }

  func validatePreservedHistory() {
    flowHistoryStore.validatePreservedHistory()
    batteryHistoryStore.validatePreservedHistory()
    priceHistoryStore.validatePreservedHistory()
  }

  @discardableResult
  func resetHistory() -> Task<Void, Never>? {
    awaitAll(
      flowHistoryStore.reset(),
      batteryHistoryStore.reset(),
      priceHistoryStore.reset()
    )
  }

  @discardableResult
  func invalidateHistory() -> Task<Void, Never>? {
    awaitAll(
      flowHistoryStore.invalidate(),
      batteryHistoryStore.invalidate(),
      priceHistoryStore.invalidate()
    )
  }

  private func awaitAll(
    _ tasks: Task<Void, Never>?...
  ) -> Task<Void, Never>? {
    let tasks = tasks.compactMap { $0 }
    guard !tasks.isEmpty else { return nil }
    return Task {
      for task in tasks {
        await task.value
      }
    }
  }
}

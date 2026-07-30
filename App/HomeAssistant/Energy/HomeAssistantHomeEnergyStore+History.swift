import Foundation

extension HomeAssistantHomeEnergyStore {
  func reloadHistory() {
    batteryHistoryStore.reload()
    priceHistoryStore.reload()
  }

  func recordHistory(
    snapshot: HomeAssistantHomeEnergySnapshot,
    at timestamp: Date
  ) {
    batteryHistoryStore.record(snapshot: snapshot, at: timestamp)
    priceHistoryStore.record(snapshot: snapshot, at: timestamp)
  }

  @discardableResult
  func resetHistory() -> Task<Void, Never>? {
    awaitBoth(
      batteryHistoryStore.reset(),
      priceHistoryStore.reset()
    )
  }

  @discardableResult
  func invalidateHistory() -> Task<Void, Never>? {
    awaitBoth(
      batteryHistoryStore.invalidate(),
      priceHistoryStore.invalidate()
    )
  }

  private func awaitBoth(
    _ first: Task<Void, Never>?,
    _ second: Task<Void, Never>?
  ) -> Task<Void, Never>? {
    guard first != nil || second != nil else { return nil }
    return Task {
      await first?.value
      await second?.value
    }
  }

}

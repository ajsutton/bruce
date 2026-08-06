import Foundation

enum EnergyWidgetRefreshReconciliation {
  static let liveAppSnapshotReuseInterval: TimeInterval = 60

  enum Result: Equatable {
    case current(HomeEnergyWidgetSnapshot)
    case lastKnown(HomeEnergyWidgetSnapshot?)
  }

  static func afterFailure(
    cachedSnapshot: HomeEnergyWidgetSnapshot?,
    sourceIdentifier: String?,
    store: HomeEnergyWidgetSnapshotStore?
  ) -> Result {
    guard sourceIdentifier != nil else { return .lastKnown(cachedSnapshot) }
    if let newerSnapshot = try? store?.loadNewer(
      than: cachedSnapshot,
      sourceIdentifier: sourceIdentifier
    ) {
      return .current(newerSnapshot)
    }
    return .lastKnown(cachedSnapshot)
  }

  static func currentLiveAppSnapshot(
    _ snapshot: HomeEnergyWidgetSnapshot?,
    expectedSourceIdentifier: String?,
    currentSourceIdentifier: String?,
    at date: Date
  ) -> HomeEnergyWidgetSnapshot? {
    guard let snapshot,
      let expectedSourceIdentifier,
      currentSourceIdentifier == expectedSourceIdentifier,
      snapshot.sourceIdentifier == expectedSourceIdentifier,
      snapshot.readingsAreCurrent,
      snapshot.importCostIsCurrent,
      snapshot.feedInEarningsIsCurrent
    else { return nil }
    let age = date.timeIntervalSince(snapshot.capturedAt)
    guard age >= 0, age < liveAppSnapshotReuseInterval else { return nil }
    return snapshot
  }
}

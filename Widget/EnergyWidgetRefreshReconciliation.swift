import Foundation

enum EnergyWidgetRefreshReconciliation {
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
}

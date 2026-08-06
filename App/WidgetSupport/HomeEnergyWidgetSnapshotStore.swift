import Foundation

struct HomeEnergyWidgetSnapshotStore {
  enum Writer: String, CaseIterable {
    case app
    case widget
  }

  private static let snapshotKeyPrefix = "homeEnergyWidgetSnapshot"
  private let defaults: UserDefaults

  init?(defaults: UserDefaults? = BruceSharedContainer.defaults()) {
    guard let defaults else { return nil }
    self.defaults = defaults
  }

  func load(sourceIdentifier: String? = nil) throws -> HomeEnergyWidgetSnapshot? {
    try Writer.allCases.compactMap(loadUnfiltered(writer:)).filter {
      sourceIdentifier == nil || $0.sourceIdentifier == sourceIdentifier
    }.max {
      $0.capturedAt < $1.capturedAt
    }
  }

  func load(
    writer: Writer,
    sourceIdentifier: String? = nil
  ) throws -> HomeEnergyWidgetSnapshot? {
    let snapshot = try loadUnfiltered(writer: writer)
    guard sourceIdentifier == nil || snapshot?.sourceIdentifier == sourceIdentifier else {
      return nil
    }
    return snapshot
  }

  func save(_ snapshot: HomeEnergyWidgetSnapshot, writer: Writer) throws {
    defaults.set(
      try JSONEncoder().encode(snapshot),
      forKey: Self.snapshotKey(writer: writer)
    )
  }

  func saveAndLoadNewest(
    _ snapshot: HomeEnergyWidgetSnapshot,
    writer: Writer
  ) throws -> HomeEnergyWidgetSnapshot {
    try save(snapshot, writer: writer)
    return try load(sourceIdentifier: snapshot.sourceIdentifier) ?? snapshot
  }

  func loadNewer(
    than snapshot: HomeEnergyWidgetSnapshot?,
    sourceIdentifier: String?
  ) throws -> HomeEnergyWidgetSnapshot? {
    guard let newest = try load(sourceIdentifier: sourceIdentifier) else { return nil }
    guard let snapshot else { return newest }
    return newest.capturedAt > snapshot.capturedAt ? newest : nil
  }

  func clear() {
    for writer in Writer.allCases {
      defaults.removeObject(forKey: Self.snapshotKey(writer: writer))
    }
  }

  private func loadUnfiltered(writer: Writer) throws -> HomeEnergyWidgetSnapshot? {
    guard let data = defaults.data(forKey: Self.snapshotKey(writer: writer)) else {
      return nil
    }
    return try JSONDecoder().decode(HomeEnergyWidgetSnapshot.self, from: data)
  }

  private static func snapshotKey(writer: Writer) -> String {
    "\(snapshotKeyPrefix).\(writer.rawValue)"
  }
}

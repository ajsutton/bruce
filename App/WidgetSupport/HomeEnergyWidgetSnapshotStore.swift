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
    try Writer.allCases.compactMap(load(writer:)).filter {
      sourceIdentifier == nil || $0.sourceIdentifier == sourceIdentifier
    }.max {
      $0.capturedAt < $1.capturedAt
    }
  }

  func save(_ snapshot: HomeEnergyWidgetSnapshot, writer: Writer) throws {
    defaults.set(
      try JSONEncoder().encode(snapshot),
      forKey: Self.snapshotKey(writer: writer)
    )
  }

  func clear() {
    for writer in Writer.allCases {
      defaults.removeObject(forKey: Self.snapshotKey(writer: writer))
    }
  }

  private func load(writer: Writer) throws -> HomeEnergyWidgetSnapshot? {
    guard let data = defaults.data(forKey: Self.snapshotKey(writer: writer)) else {
      return nil
    }
    return try JSONDecoder().decode(HomeEnergyWidgetSnapshot.self, from: data)
  }

  private static func snapshotKey(writer: Writer) -> String {
    "\(snapshotKeyPrefix).\(writer.rawValue)"
  }
}

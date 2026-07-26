import Combine
import Foundation

@MainActor
protocol BruceModeStoring: AnyObject {
  var syncedPreferenceChanges: AnyPublisher<Void, Never> { get }

  func prepareForSynchronization()
  func hasUnpublishedLocalChange() -> Bool
  func loadLocalMode() -> BruceMode?
  func loadSyncedMode() -> BruceMode?
  func saveLocalMode(_ mode: BruceMode)
  func saveMode(_ mode: BruceMode)
}

@MainActor
protocol UbiquitousKeyValueStoring: AnyObject {
  func object(forKey key: String) -> Any?
  func set(_ value: Any?, forKey key: String)
  func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStoring {}

@MainActor
final class SyncedBruceModeStore: BruceModeStoring {
  private static let mirroredStorageKey = "bruceModeLastMirrored"

  private let defaults: UserDefaults
  private let ubiquitousStore: any UbiquitousKeyValueStoring
  private let notificationCenter: NotificationCenter

  init(
    defaults: UserDefaults = .standard,
    ubiquitousStore: any UbiquitousKeyValueStoring = NSUbiquitousKeyValueStore.default,
    notificationCenter: NotificationCenter = .default
  ) {
    self.defaults = defaults
    self.ubiquitousStore = ubiquitousStore
    self.notificationCenter = notificationCenter
  }

  var syncedPreferenceChanges: AnyPublisher<Void, Never> {
    notificationCenter.publisher(
      for: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: ubiquitousStore
    )
    .map { _ in () }
    .eraseToAnyPublisher()
  }

  func prepareForSynchronization() {
    _ = ubiquitousStore.synchronize()
  }

  func hasUnpublishedLocalChange() -> Bool {
    guard let localMode = loadLocalMode() else {
      return false
    }
    return localMode != mode(from: defaults.object(forKey: Self.mirroredStorageKey))
  }

  func loadLocalMode() -> BruceMode? {
    mode(from: defaults.object(forKey: BruceMode.storageKey))
  }

  func loadSyncedMode() -> BruceMode? {
    mode(from: ubiquitousStore.object(forKey: BruceMode.storageKey))
  }

  func saveLocalMode(_ mode: BruceMode) {
    defaults.set(mode.isFullBruce, forKey: BruceMode.storageKey)
    defaults.set(mode.isFullBruce, forKey: Self.mirroredStorageKey)
  }

  func saveMode(_ mode: BruceMode) {
    saveLocalMode(mode)
    ubiquitousStore.set(mode.isFullBruce, forKey: BruceMode.storageKey)
  }

  private func mode(from storedValue: Any?) -> BruceMode? {
    if let isFullBruce = storedValue as? Bool {
      return isFullBruce ? .full : .standard
    }
    if let rawValue = storedValue as? String {
      return BruceMode(rawValue: rawValue)
    }
    return nil
  }
}

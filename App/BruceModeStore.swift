import Foundation

@MainActor
protocol BruceModeStoring: AnyObject {
  func loadMode() -> BruceMode?
  func saveMode(_ mode: BruceMode)
}

@MainActor
final class BruceModeStore: BruceModeStoring {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func loadMode() -> BruceMode? {
    mode(from: defaults.object(forKey: BruceMode.storageKey))
  }

  func saveMode(_ mode: BruceMode) {
    defaults.set(mode.isFullBruce, forKey: BruceMode.storageKey)
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

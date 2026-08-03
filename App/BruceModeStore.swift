import Foundation

#if os(iOS)
  import WidgetKit
#endif

@MainActor
protocol BruceModeStoring: AnyObject {
  func loadMode() -> BruceMode?
  func saveMode(_ mode: BruceMode)
}

@MainActor
final class BruceModeStore: BruceModeStoring {
  private let defaults: UserDefaults
  private let sharedDefaults: UserDefaults?

  init(
    defaults: UserDefaults = .standard,
    sharedDefaults: UserDefaults? = BruceSharedContainer.defaults()
  ) {
    self.defaults = defaults
    self.sharedDefaults = sharedDefaults
  }

  func loadMode() -> BruceMode? {
    mode(from: defaults.object(forKey: BruceMode.storageKey))
  }

  func saveMode(_ mode: BruceMode) {
    defaults.set(mode.isFullBruce, forKey: BruceMode.storageKey)
    sharedDefaults?.set(mode.isFullBruce, forKey: BruceMode.storageKey)
    #if os(iOS)
      WidgetCenter.shared.reloadTimelines(ofKind: EnergyWidgetKind.value)
    #endif
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

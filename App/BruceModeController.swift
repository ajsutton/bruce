import Combine
import Foundation
import OSLog

protocol BruceModeStoring: AnyObject {
  func loadMode() -> BruceMode
  func saveMode(_ mode: BruceMode)
}

final class UserDefaultsBruceModeStore: BruceModeStoring {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func loadMode() -> BruceMode {
    guard let rawValue = defaults.string(forKey: BruceMode.storageKey) else {
      return .standard
    }
    return BruceMode(rawValue: rawValue) ?? .standard
  }

  func saveMode(_ mode: BruceMode) {
    defaults.set(mode.rawValue, forKey: BruceMode.storageKey)
  }
}

@MainActor
final class BruceModeController: ObservableObject {
  @Published private(set) var mode = BruceMode.standard
  @Published private(set) var isTransitioning = false
  @Published var appIconErrorMessage: String?

  private let initialMode: BruceMode
  private let store: any BruceModeStoring
  private let iconApplier: any AppIconApplying
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Bruce",
    category: "BrandMode"
  )
  private var hasSynchronized = false

  init(
    store: any BruceModeStoring = UserDefaultsBruceModeStore(),
    iconApplier: any AppIconApplying = AppIconController()
  ) {
    self.store = store
    self.iconApplier = iconApplier
    initialMode = store.loadMode()
  }

  func synchronize() async {
    guard !hasSynchronized else {
      return
    }
    hasSynchronized = true
    await transition(to: initialMode, shouldPersist: false)
  }

  func select(_ selectedMode: BruceMode) async {
    await transition(to: selectedMode, shouldPersist: true)
  }

  private func transition(to selectedMode: BruceMode, shouldPersist: Bool) async {
    guard !isTransitioning, selectedMode != mode || !shouldPersist else {
      return
    }

    isTransitioning = true
    defer { isTransitioning = false }

    do {
      try await iconApplier.apply(selectedMode)
      if shouldPersist {
        store.saveMode(selectedMode)
      }
      mode = selectedMode
    } catch is CancellationError {
      if !shouldPersist {
        hasSynchronized = false
      }
    } catch {
      logger.error(
        "Could not apply the selected Bruce app icon: \(String(describing: error), privacy: .private)"
      )
      if !shouldPersist {
        store.saveMode(.standard)
      }
      appIconErrorMessage = "The current look is still active."
    }
  }
}

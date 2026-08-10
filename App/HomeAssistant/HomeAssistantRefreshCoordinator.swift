import SwiftUI

@MainActor
enum HomeAssistantRefreshCoordinator {
  static func shouldObserveUpdates(while scenePhase: ScenePhase) -> Bool {
    scenePhase == .active
  }

  static func sceneDidChange(
    to scenePhase: ScenePhase,
    refreshLocalPreferences: () -> Void
  ) {
    guard scenePhase == .active else { return }
    refreshLocalPreferences()
  }
}

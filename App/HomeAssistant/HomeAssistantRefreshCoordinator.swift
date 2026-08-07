import SwiftUI

@MainActor
enum HomeAssistantRefreshCoordinator {
  static func shouldObserveUpdates(
    while scenePhase: ScenePhase,
    controlsAreActive: Bool = true
  ) -> Bool {
    scenePhase == .active && controlsAreActive
  }

  static func sceneDidChange(
    to scenePhase: ScenePhase,
    refreshLocalPreferences: () -> Void
  ) {
    guard scenePhase == .active else { return }
    refreshLocalPreferences()
  }
}

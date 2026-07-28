import SwiftUI

@MainActor
enum HomeAssistantRefreshCoordinator {
  static func sceneDidChange(
    to scenePhase: ScenePhase,
    presentation: HomeAssistantPresentation,
    refreshLocalPreferences: () -> Void,
    requestHomeRefresh: () -> Void
  ) {
    guard scenePhase == .active else { return }
    refreshLocalPreferences()
    if presentation.shouldRefresh(when: scenePhase) {
      requestHomeRefresh()
    }
  }
}

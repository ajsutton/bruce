import Foundation
import SwiftUI

/// Only pre-call work belongs to a picker. Active audio belongs to the app.
@MainActor
enum BruceVoicePresentation {
  static func shouldPresentPicker(isSelected: Bool, scenePhase: ScenePhase) -> Bool {
    isSelected && scenePhase != .background
  }

  static func dismissPicker(_ store: OpenClawVoiceStore, presenterID: UUID) {
    guard store.removePicker(id: presenterID) else { return }
    dismissPicker(store)
  }

  static func dismissPicker(_ store: OpenClawVoiceStore) {
    guard !store.hasCall, store.phase != .idle, store.phase != .failed
    else { return }
    store.end(returnToPicker: false)
  }
}

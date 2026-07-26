import SwiftUI

@main
@MainActor
struct BruceApp: App {
  @StateObject private var modeController = BruceModeController()

  var body: some Scene {
    WindowGroup {
      ContentView(modeController: modeController)
        .tint(modeController.mode.accentColor)
    }
  }
}

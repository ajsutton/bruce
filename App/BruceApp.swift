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

    #if os(macOS)
      Settings {
        BruceSettingsView(modeController: modeController)
          .tint(modeController.mode.accentColor)
      }
    #endif
  }
}

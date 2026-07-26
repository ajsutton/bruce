import SwiftUI

@main
@MainActor
struct BruceApp: App {
  @StateObject private var modeController = BruceModeController()
  @StateObject private var setupStore: HomeAssistantSetupStore

  init() {
    let loader = URLSessionHomeAssistantHTTPDataLoader()
    let authenticationClient = HomeAssistantAuthenticationClient(loader: loader)
    let webAuthenticationPresenter = HomeAssistantWebAuthenticationPresenter()
    let session = HomeAssistantSession(
      credentialStore: KeychainHomeAssistantCredentialStore(),
      authenticationClient: authenticationClient,
      loader: loader
    )
    let connection = HomeAssistantConnectionCoordinator(
      authenticationClient: authenticationClient,
      browser: webAuthenticationPresenter,
      session: session
    )
    _setupStore = StateObject(
      wrappedValue: HomeAssistantSetupStore(
        discovery: HomeAssistantDiscoveryClient(browser: NetworkHomeAssistantDiscovery()),
        connection: connection,
        webAuthenticationPresenter: webAuthenticationPresenter
      )
    )
  }

  var body: some Scene {
    WindowGroup("Bruce", id: "main") {
      ContentView(modeController: modeController, setupStore: setupStore)
        .tint(modeController.mode.accentColor)
    }

    #if os(macOS)
      Settings {
        BruceSettingsView(modeController: modeController, setupStore: setupStore)
          .tint(modeController.mode.accentColor)
      }
    #endif
  }
}

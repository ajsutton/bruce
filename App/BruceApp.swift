import SwiftUI

@main
@MainActor
struct BruceApp: App {
  @StateObject private var modeController = BruceModeController()
  @StateObject private var setupStore: HomeAssistantSetupStore
  @StateObject private var temperatureStore: HomeAssistantTemperatureStore
  #if os(macOS)
    @StateObject private var settingsNavigation = BruceSettingsNavigation()
  #endif

  init() {
    HomeAssistantMaterialDesignIcon.prepare()
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "net.symphonious.bruce"
    let credentialService = "\(bundleIdentifier).home-assistant"
    let legacyCredentialService =
      bundleIdentifier == "net.symphonious.bruce.debug"
      ? "net.symphonious.bruce.home-assistant"
      : nil
    let loader = URLSessionHomeAssistantHTTPDataLoader()
    let authenticationClient = HomeAssistantAuthenticationClient(loader: loader)
    let webAuthenticationPresenter = HomeAssistantWebAuthenticationPresenter()
    let session = HomeAssistantSession(
      credentialStore: KeychainHomeAssistantCredentialStore(
        service: credentialService,
        legacyService: legacyCredentialService
      ),
      authenticationClient: authenticationClient,
      loader: loader
    )
    let connection = HomeAssistantConnectionCoordinator(
      authenticationClient: authenticationClient,
      browser: webAuthenticationPresenter,
      session: session
    )
    let setupStore = HomeAssistantSetupStore(
      discovery: HomeAssistantDiscoveryClient(browser: NetworkHomeAssistantDiscovery()),
      connection: connection,
      webAuthenticationPresenter: webAuthenticationPresenter
    )
    _setupStore = StateObject(wrappedValue: setupStore)
    _temperatureStore = StateObject(
      wrappedValue: HomeAssistantTemperatureStore(
        loader: HomeAssistantAPIClient(session: session),
        onAuthenticationRequired: {
          setupStore.requireReauthentication()
        }
      )
    )
  }

  var body: some Scene {
    WindowGroup("Bruce", id: "main") {
      #if os(macOS)
        ContentView(
          modeController: modeController,
          setupStore: setupStore,
          temperatureStore: temperatureStore,
          settingsNavigation: settingsNavigation
        )
        .tint(modeController.mode.accentColor)
      #else
        ContentView(
          modeController: modeController,
          setupStore: setupStore,
          temperatureStore: temperatureStore
        )
        .tint(modeController.mode.accentColor)
      #endif
    }

    #if os(macOS)
      Settings {
        BruceSettingsView(
          modeController: modeController,
          setupStore: setupStore,
          settingsNavigation: settingsNavigation
        )
        .tint(modeController.mode.accentColor)
      }
    #endif
  }
}

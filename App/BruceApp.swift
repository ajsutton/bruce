import SwiftUI

@main
@MainActor
struct BruceApp: App {
  #if os(iOS)
    @UIApplicationDelegateAdaptor(BruceAppDelegate.self) private var appDelegate
  #endif
  @StateObject private var modeController = BruceModeController()
  @StateObject private var setupStore: HomeAssistantSetupStore
  @StateObject private var temperatureStore: HomeAssistantTemperatureStore
  @StateObject private var chargingStore: HomeAssistantEVChargingStore
  @StateObject private var homeEnergyStore: HomeAssistantHomeEnergyStore
  #if os(macOS)
    @StateObject private var settingsNavigation = BruceSettingsNavigation()
  #endif

  init() {
    HomeAssistantMaterialDesignIcon.prepare()
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "net.symphonious.bruce"
    let credentialService = "\(bundleIdentifier).home-assistant"
    let legacyCredentialService = Self.legacyCredentialService(for: bundleIdentifier)
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
    let apiClient = HomeAssistantAPIClient(session: session)
    _setupStore = StateObject(wrappedValue: setupStore)
    _chargingStore = StateObject(
      wrappedValue: HomeAssistantEVChargingStore(
        client: apiClient,
        onAuthenticationRequired: {
          setupStore.requireReauthentication()
        }
      )
    )
    _homeEnergyStore = StateObject(
      wrappedValue: Self.homeEnergyStore(loader: apiClient, setupStore: setupStore)
    )
    _temperatureStore = StateObject(
      wrappedValue: HomeAssistantTemperatureStore(
        loader: HomeAssistantTemperatureStream(
          session: session,
          apiClient: apiClient
        ),
        controller: apiClient,
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
          chargingStore: chargingStore,
          homeEnergyStore: homeEnergyStore,
          settingsNavigation: settingsNavigation
        )
        .tint(modeController.mode.accentColor)
      #else
        ContentView(
          modeController: modeController,
          setupStore: setupStore,
          temperatureStore: temperatureStore,
          chargingStore: chargingStore,
          homeEnergyStore: homeEnergyStore
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

  private static func legacyCredentialService(for bundleIdentifier: String) -> String? {
    bundleIdentifier == "net.symphonious.bruce.debug"
      ? "net.symphonious.bruce.home-assistant"
      : nil
  }

  private static func homeEnergyStore(
    loader: any HomeAssistantHomeEnergyLoading,
    setupStore: HomeAssistantSetupStore
  ) -> HomeAssistantHomeEnergyStore {
    HomeAssistantHomeEnergyStore(
      loader: loader,
      onAuthenticationRequired: {
        setupStore.requireReauthentication()
      }
    )
  }
}

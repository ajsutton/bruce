import Foundation

@MainActor
struct BruceHomeAssistantDependencies {
  let setupStore: HomeAssistantSetupStore
  let temperatureStore: HomeAssistantTemperatureStore
  let chargingStore: HomeAssistantEVChargingStore
  let garageDoorStore: HomeAssistantGarageDoorStore
  let homeEnergyStore: HomeAssistantHomeEnergyStore
  let observationCoordinator: HomeAssistantObservationCoordinator

  init() {
    let context = Self.context()
    setupStore = context.setupStore
    let chargingStore = HomeAssistantEVChargingStore(
      client: HomeAssistantEVChargingStream(
        states: context.states,
        controller: context.apiClient
      ),
      onAuthenticationRequired: context.requireReauthentication
    )
    let homeEnergyStore = HomeAssistantHomeEnergyStore(
      loader: HomeAssistantHomeEnergyStream(
        states: context.states,
        loader: context.apiClient,
        dailyTotalsLoader: HomeAssistantDailyEnergyTotalsClient(
          session: context.session
        )
      ),
      onAuthenticationRequired: context.requireReauthentication
    )
    let garageDoorStore = HomeAssistantGarageDoorStore(
      loader: HomeAssistantGarageDoorStream(
        states: context.states,
        registryLoader: HomeAssistantRegistryClient(session: context.session)
      ),
      controller: context.apiClient,
      onAuthenticationRequired: context.requireReauthentication
    )
    let temperatureStore = HomeAssistantTemperatureStore(
      loader: HomeAssistantTemperatureStream(
        states: context.states,
        apiClient: context.apiClient
      ),
      controller: context.apiClient,
      onAuthenticationRequired: context.requireReauthentication
    )
    self.chargingStore = chargingStore
    self.garageDoorStore = garageDoorStore
    self.homeEnergyStore = homeEnergyStore
    self.temperatureStore = temperatureStore
    observationCoordinator = HomeAssistantObservationCoordinator(
      temperatureStore: temperatureStore,
      chargingStore: chargingStore,
      garageDoorStore: garageDoorStore,
      homeEnergyStore: homeEnergyStore,
      refreshStateFeed: { await context.states.refresh() },
      resetStateFeed: { await context.states.reset() },
      serverUpdates: { await context.states.stateUpdates() }
    )
  }

  private static func context() -> Context {
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "net.symphonious.bruce"
    let loader = URLSessionHomeAssistantHTTPDataLoader()
    let authenticationClient = HomeAssistantAuthenticationClient(loader: loader)
    let webAuthenticationPresenter = HomeAssistantWebAuthenticationPresenter()
    let session = HomeAssistantSession(
      credentialStore: KeychainHomeAssistantCredentialStore(
        service: "\(bundleIdentifier).home-assistant",
        legacyService: legacyCredentialService(for: bundleIdentifier)
      ),
      authenticationClient: authenticationClient,
      loader: loader
    )
    let setupStore = HomeAssistantSetupStore(
      discovery: HomeAssistantDiscoveryClient(browser: NetworkHomeAssistantDiscovery()),
      connection: HomeAssistantConnectionCoordinator(
        authenticationClient: authenticationClient,
        browser: webAuthenticationPresenter,
        session: session
      ),
      webAuthenticationPresenter: webAuthenticationPresenter
    )
    let apiClient = HomeAssistantAPIClient(session: session)
    return Context(
      setupStore: setupStore,
      session: session,
      apiClient: apiClient,
      states: HomeAssistantStateHub(
        source: HomeAssistantStateStream(session: session, apiClient: apiClient)
      )
    )
  }

  private static func legacyCredentialService(for bundleIdentifier: String) -> String? {
    bundleIdentifier == "net.symphonious.bruce.debug"
      ? "net.symphonious.bruce.home-assistant"
      : nil
  }

  private struct Context {
    let setupStore: HomeAssistantSetupStore
    let session: HomeAssistantSession
    let apiClient: HomeAssistantAPIClient
    let states: HomeAssistantStateHub

    var requireReauthentication: @MainActor @Sendable () -> Void {
      { setupStore.requireReauthentication() }
    }
  }
}

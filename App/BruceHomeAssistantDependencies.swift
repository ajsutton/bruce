import Foundation
import WidgetKit

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
    let homeEnergyStore = Self.homeEnergyStore(context: context)
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
    let observationCoordinator = HomeAssistantObservationCoordinator(
      temperatureStore: temperatureStore,
      chargingStore: chargingStore,
      garageDoorStore: garageDoorStore,
      homeEnergyStore: homeEnergyStore,
      refreshStateFeed: { await context.states.refresh() },
      resetStateFeed: { await context.states.reset() },
      serverUpdates: { await context.states.stateUpdates() }
    )
    context.setupStore.setConnectionCheckDidSucceed { [weak observationCoordinator] in
      await observationCoordinator?.refresh()
    }
    self.observationCoordinator = observationCoordinator
  }

  private static func context() -> Context {
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "net.symphonious.bruce"
    let loader = URLSessionHomeAssistantHTTPDataLoader()
    let authenticationClient = HomeAssistantAuthenticationClient(loader: loader)
    let webAuthenticationPresenter = HomeAssistantWebAuthenticationPresenter()
    let session = HomeAssistantSession(
      credentialStore: KeychainHomeAssistantCredentialStore(
        service: sharedCredentialService(for: bundleIdentifier),
        legacyService: legacyCredentialService(for: bundleIdentifier),
        accessGroup: sharedCredentialAccessGroup(),
        connectionDidChange: updateWidgetConnection
      ),
      authenticationClient: authenticationClient,
      loader: loader
    )
    let apiClient = HomeAssistantAPIClient(session: session)
    let states = HomeAssistantStateHub(
      source: HomeAssistantStateStream(session: session, apiClient: apiClient)
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
    return Context(
      setupStore: setupStore,
      session: session,
      apiClient: apiClient,
      states: states
    )
  }

  private static func homeEnergyStore(context: Context) -> HomeAssistantHomeEnergyStore {
    let widgetPublisher = HomeEnergyWidgetSnapshotPublisher()
    return HomeAssistantHomeEnergyStore(
      loader: HomeAssistantHomeEnergyStream(
        states: context.states,
        loader: context.apiClient,
        dailyTotalsLoader: HomeAssistantDailyEnergyTotalsClient(
          session: context.session
        )
      ),
      onAuthenticationRequired: context.requireReauthentication,
      publishWidgetSnapshot: { snapshot, capturedAt in
        widgetPublisher.publish(snapshot, capturedAt: capturedAt)
      }
    )
  }

  private static func sharedCredentialService(for bundleIdentifier: String) -> String {
    BruceSharedKeychain.credentialService
  }

  private static func sharedCredentialAccessGroup() -> String? {
    BruceSharedKeychain.accessGroup()
  }

  nonisolated private static func updateWidgetConnection(
    _ credentials: HomeAssistantCredentials?
  ) {
    let sourceIdentifier = credentials.map {
      BruceSharedHomeAssistant.sourceIdentifier(
        instanceID: $0.instanceID,
        internalURL: $0.internalURL,
        externalURL: $0.externalURL
      )
    }
    guard BruceSharedHomeAssistant.storedSourceIdentifier() != sourceIdentifier else { return }
    HomeEnergyWidgetSnapshotStore()?.clear()
    BruceSharedHomeAssistant.clearWidgetRoute()
    BruceSharedHomeAssistant.storeSourceIdentifier(sourceIdentifier)
    WidgetCenter.shared.reloadTimelines(ofKind: EnergyWidgetKind.value)
  }

  private static func legacyCredentialService(for bundleIdentifier: String) -> String? {
    "\(bundleIdentifier).home-assistant"
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

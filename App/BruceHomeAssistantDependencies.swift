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
    let chargingStore = HomeAssistantEVChargingStore(
      client: HomeAssistantEVChargingStream(
        states: context.states,
        controller: context.apiClient
      )
    )
    let homeEnergyStore = Self.homeEnergyStore(context: context)
    let garageDoorStore = HomeAssistantGarageDoorStore(
      loader: HomeAssistantGarageDoorStream(
        states: context.states,
        registryLoader: HomeAssistantRegistryClient(commands: context.states)
      ),
      controller: context.apiClient
    )
    let temperatureStore = HomeAssistantTemperatureStore(
      loader: HomeAssistantTemperatureStream(
        states: context.states,
        apiClient: context.apiClient
      ),
      controller: context.apiClient
    )
    self.chargingStore = chargingStore
    self.garageDoorStore = garageDoorStore
    self.homeEnergyStore = homeEnergyStore
    self.temperatureStore = temperatureStore
    setupStore = context.makeSetupStore {
      try await temperatureStore.requireFreshLiveData(from: context.states)
    }
    let observationCoordinator = HomeAssistantObservationCoordinator(
      temperatureStore: temperatureStore,
      chargingStore: chargingStore,
      garageDoorStore: garageDoorStore,
      homeEnergyStore: homeEnergyStore,
      refreshStateFeed: { await context.states.refresh() },
      setStateFeedActivity: { await context.states.setApplicationActive($0) },
      sendWakeHint: { await context.states.receiveWakeHint() },
      serverUpdates: { await context.states.stateUpdates() }
    )
    self.observationCoordinator = observationCoordinator
  }

  private static func context() -> Context {
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "net.symphonious.bruce"
    let networkSession = URLSession(
      configuration: URLSessionHomeAssistantHTTPDataLoader.makeConfiguration(),
      delegate: HomeAssistantRedirectDelegate(),
      delegateQueue: nil
    )
    let loader = URLSessionHomeAssistantHTTPDataLoader(session: networkSession)
    let authenticationClient = HomeAssistantAuthenticationClient(loader: loader)
    let webAuthenticationPresenter = HomeAssistantWebAuthenticationPresenter()
    let credentialEvents = HomeAssistantCredentialEvents()
    let session = makeSession(
      bundleIdentifier: bundleIdentifier,
      authenticationClient: authenticationClient,
      loader: loader,
      credentialEvents: credentialEvents
    )
    let stateAPIClient = HomeAssistantAPIClient(session: session)
    let states = HomeAssistantConnectionSupervisor(
      session: session,
      apiClient: stateAPIClient,
      connector: URLSessionWebSocketConnector(session: networkSession),
      credentialEvents: credentialEvents
    )
    let apiClient = HomeAssistantAPIClient(
      session: session,
      climateMetadataLoader: HomeAssistantRegistryClient(commands: states)
    )
    return Context(
      session: session,
      apiClient: apiClient,
      states: states,
      makeSetupStore: { requireFeatureData in
        makeSetupStore(
          context: SetupContext(
            session: session,
            authenticationClient: authenticationClient,
            webAuthenticationPresenter: webAuthenticationPresenter,
            credentialEvents: credentialEvents,
            states: states
          ),
          requireFeatureData: requireFeatureData
        )
      }
    )
  }

  private static func makeSession(
    bundleIdentifier: String,
    authenticationClient: HomeAssistantAuthenticationClient,
    loader: URLSessionHomeAssistantHTTPDataLoader,
    credentialEvents: HomeAssistantCredentialEvents
  ) -> HomeAssistantSession {
    HomeAssistantSession(
      credentialStore: KeychainHomeAssistantCredentialStore(
        service: sharedCredentialService(for: bundleIdentifier),
        legacyService: legacyCredentialService(for: bundleIdentifier),
        accessGroup: sharedCredentialAccessGroup(),
        connectionDidChange: updateWidgetConnection
      ),
      authenticationClient: authenticationClient,
      loader: loader,
      credentialEvents: credentialEvents
    )
  }

  private static func makeSetupStore(
    context: SetupContext,
    requireFeatureData: @escaping @Sendable () async throws -> Void
  ) -> HomeAssistantSetupStore {
    HomeAssistantSetupStore(
      discovery: HomeAssistantDiscoveryClient(browser: NetworkHomeAssistantDiscovery()),
      connection: HomeAssistantConnectionCoordinator(
        authenticationClient: context.authenticationClient,
        browser: context.webAuthenticationPresenter,
        session: context.session,
        supervisor: context.states,
        requireFeatureData: requireFeatureData
      ),
      webAuthenticationPresenter: context.webAuthenticationPresenter,
      credentialEvents: context.credentialEvents
    )
  }

  private static func homeEnergyStore(context: Context) -> HomeAssistantHomeEnergyStore {
    let widgetPublisher = HomeEnergyWidgetSnapshotPublisher()
    return HomeAssistantHomeEnergyStore(
      loader: HomeAssistantHomeEnergyStream(
        states: context.states,
        loader: context.apiClient,
        dailyTotalsLoader: HomeAssistantDailyEnergyTotalsClient(
          commands: context.states
        )
      ),
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
    let session: HomeAssistantSession
    let apiClient: HomeAssistantAPIClient
    let states: HomeAssistantConnectionSupervisor
    let makeSetupStore:
      @MainActor (@escaping @Sendable () async throws -> Void) -> HomeAssistantSetupStore
  }

  private struct SetupContext {
    let session: HomeAssistantSession
    let authenticationClient: HomeAssistantAuthenticationClient
    let webAuthenticationPresenter: HomeAssistantWebAuthenticationPresenter
    let credentialEvents: HomeAssistantCredentialEvents
    let states: HomeAssistantConnectionSupervisor
  }
}

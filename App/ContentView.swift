import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var homeAssistantCoordinator: HomeAssistantObservationCoordinator
  #if os(macOS)
    @Environment(\.openSettings) private var openSettings
  #else
    @EnvironmentObject private var sceneDelegate: BruceSceneDelegate
  #endif
  @ObservedObject var modeController: BruceModeController
  @ObservedObject var setupStore: HomeAssistantSetupStore
  let temperatureStore: HomeAssistantTemperatureStore
  let chargingStore: HomeAssistantEVChargingStore
  let garageDoorStore: HomeAssistantGarageDoorStore
  let homeEnergyStore: HomeAssistantHomeEnergyStore
  #if os(macOS)
    @ObservedObject var settingsNavigation: BruceSettingsNavigation
  #else
    @State private var showsConnectionManagement = false
  #endif

  private var mode: BruceMode {
    modeController.mode
  }

  private var copy: AppCopy {
    AppCopy(mode: mode)
  }

  var body: some View {
    content
      .preferredColorScheme(mode.isFullBruce ? .dark : nil)
      .task {
        await modeController.restore()
        #if os(iOS)
          await setupStore.restoreSavedConnection()
        #endif
      }
      #if os(iOS)
        .task(id: presentation.access) {
          await homeAssistantCoordinator.synchronize(with: presentation.access)
        }
        .task(id: shouldObserveHomeUpdates) {
          await homeAssistantCoordinator.observeUpdates(
            while: shouldObserveHomeUpdates
          )
        }
      #endif
      .onChange(of: scenePhase) { _, newScenePhase in
        HomeAssistantRefreshCoordinator.sceneDidChange(
          to: newScenePhase,
          refreshLocalPreferences: modeController.requestLocalPreferenceRefresh
        )
      }
      .alert(
        copy.iconChangeFailedTitle,
        isPresented: Binding(
          get: { modeController.hasAppIconError },
          set: { isPresented in
            if !isPresented {
              modeController.dismissAppIconError()
            }
          }
        )
      ) {
        Button(copy.dismiss, role: .cancel) {}
      } message: {
        Text(copy.iconChangeFailedMessage)
      }
      #if os(iOS)
        .sheet(isPresented: $showsConnectionManagement) {
          HomeAssistantSetupView(
            store: setupStore,
            mode: mode,
            startsInConnectionManagement: true
          )
        }
        .onChange(of: sceneDelegate.manageConnectionRequestID, initial: true) { _, requestID in
          guard requestID > 0 else {
            return
          }
          showsConnectionManagement = true
        }
      #endif
  }

  @ViewBuilder
  private var content: some View {
    if presentation.screen == .panels {
      BrucePanelsView(
        temperatureStore: temperatureStore,
        chargingStore: chargingStore,
        garageDoorStore: garageDoorStore,
        homeEnergyStore: homeEnergyStore,
        mode: mode,
        isConnecting: presentation.isConnecting,
        connectionProblem: presentation.connectionProblem,
        serverStatus: homeAssistantCoordinator.serverStatus,
        manageConnection: manageConnection,
        requestHomeRefresh: requestHomeRefresh,
        isRemovingConnection: setupStore.isDisconnecting
      )
    } else {
      #if os(macOS)
        ContentUnavailableView {
          Label(copy.notConnectedTitle, systemImage: "house.fill")
        } description: {
          Text(copy.notConnectedDescription)
        } actions: {
          Button(copy.connectHomeAssistant) {
            manageConnection()
          }
          .buttonStyle(.borderedProminent)
        }
        .padding()
      #else
        HomeAssistantSetupView(store: setupStore, mode: mode)
      #endif
    }
  }

  private var presentation: HomeAssistantPresentation {
    HomeAssistantPresentation(
      step: setupStore.step,
      connectionCheckState: setupStore.connectionCheckState
    )
  }

  private var shouldObserveHomeUpdates: Bool {
    HomeAssistantRefreshCoordinator.shouldObserveUpdates(while: scenePhase)
  }

  private func manageConnection() {
    #if os(macOS)
      settingsNavigation.showHomeAssistant()
      openSettings()
    #else
      showsConnectionManagement = true
    #endif
  }

  private func requestHomeRefresh() {
    guard presentation.canRefresh else {
      return
    }
    Task {
      await homeAssistantCoordinator.refresh()
    }
  }
}

#Preview("Bruce") {
  previewContentView()
}

@MainActor
private func previewContentView() -> some View {
  let temperatureStore = HomeAssistantTemperatureStore(
    loader: PreviewContentTemperatureLoader()
  )
  let chargingStore = HomeAssistantEVChargingStore(
    client: PreviewContentEVChargingClient(),
    mode: .smart
  )
  let homeEnergyStore = HomeAssistantHomeEnergyStore(
    loader: PreviewContentHomeEnergyLoader()
  )
  let garageDoorStore = HomeAssistantGarageDoorStore(
    loader: PreviewContentGarageDoorLoader()
  )
  let coordinator = HomeAssistantObservationCoordinator(
    temperatureStore: temperatureStore,
    chargingStore: chargingStore,
    garageDoorStore: garageDoorStore,
    homeEnergyStore: homeEnergyStore
  )
  #if os(macOS)
    return ContentView(
      modeController: BruceModeController(
        store: PreviewBruceModeStore(),
        iconApplier: PreviewAppIconApplier()
      ),
      setupStore: HomeAssistantSetupStore(discovery: PreviewHomeAssistantDiscovery()),
      temperatureStore: temperatureStore,
      chargingStore: chargingStore,
      garageDoorStore: garageDoorStore,
      homeEnergyStore: homeEnergyStore,
      settingsNavigation: BruceSettingsNavigation()
    )
    .environmentObject(coordinator)
  #else
    return ContentView(
      modeController: BruceModeController(
        store: PreviewBruceModeStore(),
        iconApplier: PreviewAppIconApplier()
      ),
      setupStore: HomeAssistantSetupStore(discovery: PreviewHomeAssistantDiscovery()),
      temperatureStore: temperatureStore,
      chargingStore: chargingStore,
      garageDoorStore: garageDoorStore,
      homeEnergyStore: homeEnergyStore
    )
    .environmentObject(BruceSceneDelegate())
    .environmentObject(coordinator)
  #endif
}

private struct PreviewContentGarageDoorLoader: HomeAssistantGarageDoorLoading {
  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] {
    []
  }
}

@MainActor
final class PreviewBruceModeStore: BruceModeStoring {
  func loadMode() -> BruceMode? { .standard }
  func saveMode(_ mode: BruceMode) {}
}

@MainActor
struct PreviewAppIconApplier: AppIconApplying {
  func apply(_ mode: BruceMode) async throws {}
}

private struct PreviewHomeAssistantDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}

private struct PreviewContentEVChargingClient: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    .smart
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    mode
  }
}

private struct PreviewContentHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }
}

private struct PreviewContentTemperatureLoader: HomeAssistantTemperatureLoading {
  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      continuation.yield(.live([]))
      continuation.finish()
    }
  }
}

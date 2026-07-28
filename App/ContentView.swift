import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  #if os(macOS)
    @Environment(\.openSettings) private var openSettings
  #endif
  @ObservedObject var modeController: BruceModeController
  @ObservedObject var setupStore: HomeAssistantSetupStore
  @ObservedObject var temperatureStore: HomeAssistantTemperatureStore
  @ObservedObject var chargingStore: HomeAssistantEVChargingStore
  @ObservedObject var homeEnergyStore: HomeAssistantHomeEnergyStore
  #if os(macOS)
    @ObservedObject var settingsNavigation: BruceSettingsNavigation
  #else
    @State private var showsConnectionManagement = false
  #endif
  @State private var homeRefreshRequest = 0

  private var mode: BruceMode {
    modeController.mode
  }

  var body: some View {
    content
      .preferredColorScheme(mode.isFullBruce ? .dark : nil)
      .task {
        await modeController.restore()
        await setupStore.restoreSavedConnection()
      }
      .task(id: refreshRequest) {
        await temperatureStore.synchronize(with: presentation.connection)
      }
      .task(id: refreshRequest) {
        await synchronizeChargingStore()
      }
      .task(id: refreshRequest) {
        await homeEnergyStore.synchronize(with: presentation.connection)
      }
      .onChange(of: scenePhase) { _, newScenePhase in
        guard newScenePhase == .active else {
          return
        }
        modeController.requestLocalPreferenceRefresh()
        if presentation.shouldRefresh(when: newScenePhase) {
          homeRefreshRequest += 1
        }
      }
      .alert(
        "Bruce couldn’t change the app icon",
        isPresented: Binding(
          get: { modeController.appIconErrorMessage != nil },
          set: { isPresented in
            if !isPresented {
              modeController.appIconErrorMessage = nil
            }
          }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(modeController.appIconErrorMessage ?? "")
      }
      #if os(iOS)
        .sheet(isPresented: $showsConnectionManagement) {
          HomeAssistantSetupView(store: setupStore, mode: mode)
        }
      #endif
  }

  @ViewBuilder
  private var content: some View {
    if presentation.screen == .panels {
      BrucePanelsView(
        temperatureStore: temperatureStore,
        chargingStore: chargingStore,
        homeEnergyStore: homeEnergyStore,
        mode: mode,
        isConnecting: presentation.isConnecting,
        connectionProblem: presentation.connectionProblem,
        manageConnection: manageConnection,
        requestHomeRefresh: requestHomeRefresh,
        isRemovingConnection: setupStore.isDisconnecting
      )
    } else {
      #if os(macOS)
        ContentUnavailableView {
          Label("Home Assistant Isn’t Connected", systemImage: "house.fill")
        } description: {
          Text("Connect Home Assistant in Bruce Settings.")
        } actions: {
          Button("Connect Home Assistant") {
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

  private var refreshRequest: HomeAssistantRefreshRequest {
    HomeAssistantRefreshRequest(
      connection: presentation.connection,
      refreshRequest: homeRefreshRequest
    )
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
    homeRefreshRequest += 1
  }

  private func synchronizeChargingStore() async {
    switch presentation.connection {
    case .connected:
      await chargingStore.load()
    case .disconnected:
      chargingStore.reset()
    case .connecting:
      chargingStore.markConnectionInProgress()
    case .unavailable:
      chargingStore.markConnectionUnavailable()
    }
  }
}

#Preview("Bruce") {
  #if os(macOS)
    ContentView(
      modeController: BruceModeController(
        store: PreviewBruceModeStore(),
        iconApplier: PreviewAppIconApplier()
      ),
      setupStore: HomeAssistantSetupStore(discovery: PreviewHomeAssistantDiscovery()),
      temperatureStore: HomeAssistantTemperatureStore(
        loader: PreviewContentTemperatureLoader()
      ),
      chargingStore: HomeAssistantEVChargingStore(
        client: PreviewContentEVChargingClient(),
        mode: .smart
      ),
      homeEnergyStore: HomeAssistantHomeEnergyStore(
        loader: PreviewContentHomeEnergyLoader()
      ),
      settingsNavigation: BruceSettingsNavigation()
    )
  #else
    ContentView(
      modeController: BruceModeController(
        store: PreviewBruceModeStore(),
        iconApplier: PreviewAppIconApplier()
      ),
      setupStore: HomeAssistantSetupStore(discovery: PreviewHomeAssistantDiscovery()),
      temperatureStore: HomeAssistantTemperatureStore(
        loader: PreviewContentTemperatureLoader()
      ),
      chargingStore: HomeAssistantEVChargingStore(
        client: PreviewContentEVChargingClient(),
        mode: .smart
      ),
      homeEnergyStore: HomeAssistantHomeEnergyStore(
        loader: PreviewContentHomeEnergyLoader()
      )
    )
  #endif
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

private struct HomeAssistantRefreshRequest: Equatable {
  let connection: HomeAssistantConnectionState
  let refreshRequest: Int
}

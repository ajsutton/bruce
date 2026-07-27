import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  #if os(macOS)
    @Environment(\.openSettings) private var openSettings
  #endif
  @ObservedObject var modeController: BruceModeController
  @ObservedObject var setupStore: HomeAssistantSetupStore
  @ObservedObject var temperatureStore: HomeAssistantTemperatureStore
  #if os(macOS)
    @ObservedObject var settingsNavigation: BruceSettingsNavigation
  #else
    @State private var showsConnectionManagement = false
  #endif
  @State private var temperatureRefreshRequest = 0

  private var mode: BruceMode {
    modeController.mode
  }

  var body: some View {
    content
      .task {
        await modeController.restore()
        await setupStore.restoreSavedConnection()
      }
      .task(id: temperatureLoadRequest) {
        await temperatureStore.synchronize(with: presentation.connection)
      }
      .onChange(of: scenePhase) { _, newScenePhase in
        guard newScenePhase == .active else {
          return
        }
        modeController.requestLocalPreferenceRefresh()
        if presentation.shouldRefresh(when: newScenePhase) {
          temperatureRefreshRequest += 1
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
    if presentation.screen == .temperatures {
      HomeAssistantTemperatureView(
        store: temperatureStore,
        mode: mode,
        isConnecting: presentation.isConnecting,
        connectionProblem: presentation.connectionProblem,
        manageConnection: manageConnection,
        requestRefresh: requestTemperatureRefresh,
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

  private var presentation: HomeAssistantTemperaturePresentation {
    HomeAssistantTemperaturePresentation(
      step: setupStore.step,
      connectionCheckState: setupStore.connectionCheckState
    )
  }

  private var temperatureLoadRequest: TemperatureLoadRequest {
    TemperatureLoadRequest(
      connection: presentation.connection,
      refreshRequest: temperatureRefreshRequest
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

  private func requestTemperatureRefresh() {
    guard presentation.canRefresh else {
      return
    }
    temperatureRefreshRequest += 1
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

private struct TemperatureLoadRequest: Equatable {
  let connection: HomeAssistantTemperatureConnection
  let refreshRequest: Int
}

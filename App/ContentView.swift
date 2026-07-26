import Combine
import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  #if os(macOS)
    @Environment(\.openSettings) private var openSettings
  #endif
  @ObservedObject var modeController: BruceModeController
  @ObservedObject var setupStore: HomeAssistantSetupStore
  #if os(macOS)
    @ObservedObject var settingsNavigation: BruceSettingsNavigation
  #endif

  private var mode: BruceMode {
    modeController.mode
  }

  var body: some View {
    content
      .task {
        await modeController.synchronize()
        await setupStore.restoreSavedConnection()
      }
      .onChange(of: scenePhase) { _, newScenePhase in
        guard newScenePhase == .active else {
          return
        }
        modeController.requestLocalPreferenceRefresh()
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
  }

  @ViewBuilder
  private var content: some View {
    #if os(macOS)
      ContentUnavailableView {
        Label(mainStatus.title, systemImage: "house.fill")
      } description: {
        Text(mainStatus.description)
      } actions: {
        Button(mainStatus.actionTitle) {
          settingsNavigation.showHomeAssistant()
          openSettings()
        }
        .buttonStyle(.borderedProminent)
      }
      .padding()
    #else
      HomeAssistantSetupView(store: setupStore, mode: mode)
    #endif
  }

  #if os(macOS)
    private var mainStatus: HomeAssistantMainStatus {
      HomeAssistantMainStatus(
        step: setupStore.step,
        connectionCheckState: setupStore.connectionCheckState,
        isDisconnecting: setupStore.isDisconnecting
      )
    }
  #endif
}

#Preview("Bruce") {
  #if os(macOS)
    ContentView(
      modeController: BruceModeController(
        store: PreviewBruceModeStore(),
        iconApplier: PreviewAppIconApplier()
      ),
      setupStore: HomeAssistantSetupStore(discovery: PreviewHomeAssistantDiscovery()),
      settingsNavigation: BruceSettingsNavigation()
    )
  #else
    ContentView(
      modeController: BruceModeController(
        store: PreviewBruceModeStore(),
        iconApplier: PreviewAppIconApplier()
      ),
      setupStore: HomeAssistantSetupStore(discovery: PreviewHomeAssistantDiscovery())
    )
  #endif
}

@MainActor
final class PreviewBruceModeStore: BruceModeStoring {
  var syncedPreferenceChanges: AnyPublisher<Void, Never> {
    Empty().eraseToAnyPublisher()
  }

  func prepareForSynchronization() {}
  func hasUnpublishedLocalChange() -> Bool { false }
  func loadLocalMode() -> BruceMode? { .standard }
  func loadSyncedMode() -> BruceMode? { nil }
  func saveLocalMode(_ mode: BruceMode) {}
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

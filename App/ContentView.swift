import Combine
import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var modeController: BruceModeController
  @ObservedObject var setupStore: HomeAssistantSetupStore

  private var mode: BruceMode {
    modeController.mode
  }

  var body: some View {
    HomeAssistantSetupView(store: setupStore, mode: mode)
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
}

#Preview("Bruce") {
  ContentView(
    modeController: BruceModeController(
      store: PreviewBruceModeStore(),
      iconApplier: PreviewAppIconApplier()
    ),
    setupStore: HomeAssistantSetupStore(discovery: PreviewHomeAssistantDiscovery())
  )
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

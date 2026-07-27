import SwiftUI

#if os(macOS)
  struct BruceSettingsView: View {
    @ObservedObject var modeController: BruceModeController
    @ObservedObject var setupStore: HomeAssistantSetupStore
    @ObservedObject var settingsNavigation: BruceSettingsNavigation
    @State private var canAutomaticallyDiscover = false

    private var isFullBruce: Binding<Bool> {
      Binding(
        get: { modeController.mode.isFullBruce },
        set: { isEnabled in
          modeController.requestSelection(isEnabled ? .full : .standard)
        }
      )
    }

    var body: some View {
      TabView(selection: $settingsNavigation.selectedSection) {
        generalSettings
          .tabItem {
            Label("General", systemImage: "gear")
          }
          .tag(BruceSettingsNavigation.Section.general)

        HomeAssistantSetupView(store: setupStore, mode: modeController.mode)
          .tabItem {
            Label("Home Assistant", systemImage: "house")
          }
          .tag(BruceSettingsNavigation.Section.homeAssistant)
      }
      .frame(width: 560, height: 520)
      .task {
        await modeController.restore()
        guard !Task.isCancelled,
          await setupStore.restoreSavedConnection()
        else {
          return
        }
        canAutomaticallyDiscover = true
        startDiscoveryIfNeeded()
      }
      .onChange(of: settingsNavigation.selectedSection) {
        startDiscoveryIfNeeded()
      }
      .onChange(of: setupStore.step) {
        startDiscoveryIfNeeded()
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

    private var generalSettings: some View {
      Form {
        Section {
          Toggle("Go The Full Bruce", isOn: isFullBruce)
            .disabled(modeController.isTransitioning)
        } footer: {
          Text("Changes Bruce’s icon, styling and eligible language on this device.")
        }
      }
      .formStyle(.grouped)
    }

    private func startDiscoveryIfNeeded() {
      guard canAutomaticallyDiscover,
        settingsNavigation.selectedSection == .homeAssistant
      else {
        return
      }
      setupStore.startDiscoveryIfUnconfigured()
    }
  }

  #Preview("Settings") {
    BruceSettingsView(
      modeController: BruceModeController(
        store: PreviewBruceModeStore(),
        iconApplier: PreviewAppIconApplier()
      ),
      setupStore: HomeAssistantSetupStore(discovery: PreviewSettingsDiscovery()),
      settingsNavigation: BruceSettingsNavigation()
    )
  }

  private struct PreviewSettingsDiscovery: HomeAssistantDiscovering {
    func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
      AsyncThrowingStream { continuation in
        continuation.finish()
      }
    }
  }
#endif

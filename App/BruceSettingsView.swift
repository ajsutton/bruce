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

    private var copy: AppCopy {
      AppCopy(mode: modeController.mode)
    }

    var body: some View {
      TabView(selection: $settingsNavigation.selectedSection) {
        generalSettings
          .tabItem {
            Label(copy.generalSettingsTab, systemImage: "gear")
          }
          .tag(BruceSettingsNavigation.Section.general)

        HomeAssistantSetupView(store: setupStore, mode: modeController.mode)
          .tabItem {
            Label(copy.homeAssistantSettingsTab, systemImage: "house")
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
    }

    private var generalSettings: some View {
      Form {
        Section {
          Toggle(copy.fullBruceToggle, isOn: isFullBruce)
            .disabled(modeController.isTransitioning)
        } footer: {
          Text(copy.fullBruceFooter)
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

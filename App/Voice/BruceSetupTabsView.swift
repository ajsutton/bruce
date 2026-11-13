#if os(iOS)
  import SwiftUI

  /// Voice remains available before Home Assistant has been connected.
  struct BruceSetupTabsView: View {
    let store: HomeAssistantSetupStore
    let mode: BruceMode
    @AppStorage(BrucePanel.storageKey) private var selectedPanel = BrucePanel.climate

    var body: some View {
      TabView(selection: selection) {
        Tab(
          AppCopy(mode: mode).homeAssistantSettingsTab, systemImage: "house",
          value: BrucePanel.climate
        ) {
          HomeAssistantSetupView(store: store, mode: mode)
        }
        Tab(AppCopy(mode: mode).voiceTab, systemImage: "waveform", value: BrucePanel.voice) {
          BruceVoiceDestinationView(mode: mode)
        }
      }
      .tabViewStyle(.sidebarAdaptable)
    }

    private var selection: Binding<BrucePanel> {
      Binding(
        get: { selectedPanel == .voice ? .voice : .climate },
        set: { selectedPanel = $0 }
      )
    }
  }
#endif

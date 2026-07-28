import SwiftUI

struct EnergyPanelView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var chargingStore: HomeAssistantEVChargingStore
  let mode: BruceMode
  let manageConnection: () -> Void
  let requestRefresh: () -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        HomeAssistantEVChargingCard(
          store: chargingStore,
          mode: mode,
          manageConnection: manageConnection,
          requestRefresh: requestRefresh
        )
        .padding()
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
      }
      .background(mode.panelBackgroundColor(for: colorScheme))
      .navigationTitle("Energy")
      #if os(iOS)
        .toolbarTitleDisplayMode(
          dynamicTypeSize.isAccessibilitySize ? .large : .inline
        )
      #else
        .toolbarTitleDisplayMode(.inline)
      #endif
    }
    .preferredColorScheme(mode.isFullBruce ? .dark : nil)
  }
}

#Preview("Energy") {
  EnergyPanelView(
    chargingStore: HomeAssistantEVChargingStore(
      client: PreviewEVChargingClient(),
      mode: .smart,
      activity: .charging(powerWatts: 7_024)
    ),
    mode: .standard,
    manageConnection: {},
    requestRefresh: {}
  )
  .tint(BruceMode.standard.accentColor)
}

#Preview("Energy — Full Bruce") {
  EnergyPanelView(
    chargingStore: HomeAssistantEVChargingStore(
      client: PreviewEVChargingClient(),
      mode: .smart,
      activity: .paused(reason: .homeBattery)
    ),
    mode: .full,
    manageConnection: {},
    requestRefresh: {}
  )
  .tint(BruceMode.full.accentColor)
}

private struct PreviewEVChargingClient: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    .smart
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    mode
  }
}

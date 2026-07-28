import SwiftUI

struct EnergyPanelView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var chargingStore: HomeAssistantEVChargingStore
  @ObservedObject var homeEnergyStore: HomeAssistantHomeEnergyStore
  let mode: BruceMode
  let manageConnection: () -> Void
  let requestRefresh: () -> Void

  private var copy: EnergyPanelCopy {
    EnergyPanelCopy(mode: mode)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          HomeAssistantEVChargingCard(
            store: chargingStore,
            mode: mode,
            manageConnection: manageConnection,
            requestRefresh: requestRefresh
          )
          HomeAssistantHomeEnergyCard(
            store: homeEnergyStore,
            mode: mode,
            manageConnection: manageConnection,
            requestRefresh: requestRefresh
          )
        }
        .padding()
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
      }
      .background(mode.panelBackgroundColor(for: colorScheme))
      .navigationTitle(copy.navigationTitle)
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
    homeEnergyStore: HomeAssistantHomeEnergyStore(
      loader: PreviewHomeEnergyLoader(),
      snapshot: PreviewHomeEnergyLoader.exportingSnapshot,
      isLive: true
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
    homeEnergyStore: HomeAssistantHomeEnergyStore(
      loader: PreviewHomeEnergyLoader(),
      snapshot: PreviewHomeEnergyLoader.importingSnapshot,
      isLive: true
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

private struct PreviewHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  static let exportingSnapshot = HomeAssistantHomeEnergySnapshot(
    pvPowerKilowatts: 8.4,
    batteryStateOfCharge: 76,
    homeConsumptionKilowatts: 3.1,
    gridPowerKilowatts: -2.7,
    generalPriceDollarsPerKilowattHour: 0.341,
    feedInPriceDollarsPerKilowattHour: 0.127
  )

  static let importingSnapshot = HomeAssistantHomeEnergySnapshot(
    pvPowerKilowatts: 0,
    batteryStateOfCharge: 38,
    homeConsumptionKilowatts: 4.6,
    gridPowerKilowatts: 3.9,
    generalPriceDollarsPerKilowattHour: 0.584,
    feedInPriceDollarsPerKilowattHour: -0.051
  )

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    Self.exportingSnapshot
  }
}

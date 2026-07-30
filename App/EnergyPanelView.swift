import SwiftUI

struct EnergyPanelView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var homeEnergyStore: HomeAssistantHomeEnergyStore
  let mode: BruceMode
  var showsConnectionProblems = true
  let manageConnection: () -> Void
  let requestRefresh: () -> Void
  var isEmbedded = false

  private var copy: EnergyPanelCopy {
    EnergyPanelCopy(mode: mode)
  }

  var body: some View {
    Group {
      if isEmbedded {
        panelContent
      } else {
        NavigationStack {
          ScrollView {
            panelContent
          }
          .navigationTitle(copy.navigationTitle)
          #if os(iOS)
            .toolbarTitleDisplayMode(
              dynamicTypeSize.isAccessibilitySize ? .large : .inline
            )
          #else
            .toolbarTitleDisplayMode(.inline)
          #endif
        }
      }
    }
    .background(mode.panelBackgroundColor(for: colorScheme))
    .preferredColorScheme(mode.isFullBruce ? .dark : nil)
  }

  private var panelContent: some View {
    VStack(spacing: 16) {
      HomeAssistantHomeEnergyCard(
        store: homeEnergyStore,
        mode: mode,
        showsConnectionProblems: showsConnectionProblems,
        manageConnection: manageConnection,
        requestRefresh: requestRefresh
      )
    }
    .padding()
    .frame(maxWidth: 720)
    .frame(maxWidth: .infinity)
  }
}

#Preview("Energy") {
  EnergyPanelView(
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

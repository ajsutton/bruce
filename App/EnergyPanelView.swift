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
      HomeAssistantHomeEnergyPriceChart(
        store: homeEnergyStore.priceHistoryStore,
        mode: mode
      )
      HomeAssistantHomeEnergyBatteryChart(
        store: homeEnergyStore.batteryHistoryStore,
        mode: mode
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
      isLive: true,
      batteryHistory: PreviewHomeEnergyLoader.batteryHistory,
      priceHistory: PreviewHomeEnergyLoader.priceHistory
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
      isLive: true,
      batteryHistory: PreviewHomeEnergyLoader.batteryHistory,
      priceHistory: PreviewHomeEnergyLoader.priceHistory
    ),
    mode: .full,
    manageConnection: {},
    requestRefresh: {}
  )
  .tint(BruceMode.full.accentColor)
}

#Preview("Battery chart") {
  HomeAssistantHomeEnergyBatteryChart(
    store: HomeAssistantHomeEnergyStore(
      loader: PreviewHomeEnergyLoader(),
      snapshot: PreviewHomeEnergyLoader.exportingSnapshot,
      isLive: true,
      batteryHistory: PreviewHomeEnergyLoader.batteryHistory,
      priceHistory: PreviewHomeEnergyLoader.priceHistory
    ).batteryHistoryStore,
    mode: .standard
  )
  .padding()
  .frame(width: 720)
}

#Preview("Price chart") {
  HomeAssistantHomeEnergyPriceChart(
    store: HomeAssistantHomeEnergyStore(
      loader: PreviewHomeEnergyLoader(),
      snapshot: PreviewHomeEnergyLoader.exportingSnapshot,
      isLive: true,
      batteryHistory: PreviewHomeEnergyLoader.batteryHistory,
      priceHistory: PreviewHomeEnergyLoader.priceHistory
    ).priceHistoryStore,
    mode: .standard
  )
  .padding()
  .frame(width: 720)
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

  static let batteryHistory: HomeEnergyBatteryHistory = {
    let end = Date(timeIntervalSince1970: 1_785_408_000)
    let values = [34.0, 29, 26, 24, 31, 48, 67, 79, 76]
    let readings = values.enumerated().map { index, value in
      HomeEnergyBatteryHistory.Reading(
        timestamp: end.addingTimeInterval(TimeInterval(index - 8) * 3 * 60 * 60),
        stateOfCharge: value
      )
    }
    return HomeEnergyBatteryHistory(
      interval: DateInterval(
        start: end.addingTimeInterval(-24 * 60 * 60),
        end: end
      ),
      readings: readings
    )
  }()

  static let priceHistory: HomeEnergyPriceHistory = {
    let end = Date(timeIntervalSince1970: 1_785_408_000)
    let values = [
      (general: 0.24, feedIn: 0.08),
      (general: 0.19, feedIn: 0.07),
      (general: 0.16, feedIn: 0.06),
      (general: 0.22, feedIn: 0.09),
      (general: 0.38, feedIn: 0.14),
      (general: 0.41, feedIn: 0.18),
      (general: 0.17, feedIn: 0.01),
      (general: 0.04, feedIn: -0.01),
      (general: 0.341, feedIn: 0.127),
    ]
    let readings = values.enumerated().flatMap { index, value in
      let timestamp = end.addingTimeInterval(TimeInterval(index - 8) * 3 * 60 * 60)
      return [
        HomeEnergyPriceHistory.Reading(
          tariff: .general,
          timestamp: timestamp,
          dollarsPerKilowattHour: value.general
        ),
        HomeEnergyPriceHistory.Reading(
          tariff: .feedIn,
          timestamp: timestamp,
          dollarsPerKilowattHour: value.feedIn
        ),
      ]
    }
    return HomeEnergyPriceHistory(
      interval: DateInterval(
        start: end.addingTimeInterval(-24 * 60 * 60),
        end: end
      ),
      readings: readings
    )
  }()

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    Self.exportingSnapshot
  }
}

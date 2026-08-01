import SwiftUI

struct EnergyPanelView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let homeEnergyStore: HomeAssistantHomeEnergyStore
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
    LazyVStack(spacing: 16) {
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
      HomeAssistantHomeEnergyFlowChart(
        store: homeEnergyStore.flowHistoryStore,
        mode: mode
      )
      HomeAssistantHomeEnergyBatteryChart(
        store: homeEnergyStore.batteryHistoryStore,
        mode: mode
      )
    }
    .padding(BrucePanelLayout.contentPadding)
    .frame(maxWidth: BrucePanelLayout.maximumContentWidth)
    .frame(maxWidth: .infinity)
  }
}

#Preview("Energy") {
  EnergyPanelView(
    homeEnergyStore: HomeAssistantHomeEnergyStore(
      loader: PreviewHomeEnergyLoader(),
      snapshot: PreviewHomeEnergyLoader.exportingSnapshot,
      isLive: true,
      flowHistory: PreviewHomeEnergyLoader.flowHistory,
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
      flowHistory: PreviewHomeEnergyLoader.flowHistory,
      batteryHistory: PreviewHomeEnergyLoader.batteryHistory,
      priceHistory: PreviewHomeEnergyLoader.priceHistory
    ),
    mode: .full,
    manageConnection: {},
    requestRefresh: {}
  )
  .tint(BruceMode.full.accentColor)
}

#Preview("Energy flow chart") {
  HomeAssistantHomeEnergyFlowChart(
    store: HomeAssistantHomeEnergyStore(
      loader: PreviewHomeEnergyLoader(),
      snapshot: PreviewHomeEnergyLoader.exportingSnapshot,
      isLive: true,
      flowHistory: PreviewHomeEnergyLoader.denseFlowHistory
    ).flowHistoryStore,
    mode: .standard
  )
  .padding()
  .frame(maxWidth: 720)
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
    batteryPowerKilowatts: -2.6,
    homeConsumptionKilowatts: 3.1,
    gridPowerKilowatts: -2.7,
    generalPriceDollarsPerKilowattHour: 0.341,
    feedInPriceDollarsPerKilowattHour: 0.127,
    importCostTodayDollars: 0.20,
    feedInEarningsTodayDollars: 0.91
  )

  static let importingSnapshot = HomeAssistantHomeEnergySnapshot(
    pvPowerKilowatts: 0,
    batteryStateOfCharge: 38,
    batteryPowerKilowatts: 0.7,
    homeConsumptionKilowatts: 4.6,
    gridPowerKilowatts: 3.9,
    generalPriceDollarsPerKilowattHour: 0.584,
    feedInPriceDollarsPerKilowattHour: -0.051,
    importCostTodayDollars: 4.83,
    feedInEarningsTodayDollars: 0.12
  )

  static let flowHistory: HomeEnergyFlowHistory = {
    let end = Date(timeIntervalSince1970: 1_785_408_000)
    let values = [
      (pv: 0.0, home: 1.2, grid: 0.0, battery: 1.2),
      (pv: 0.0, home: 1.0, grid: 0.0, battery: 1.0),
      (pv: 0.0, home: 1.1, grid: 0.0, battery: 1.1),
      (pv: 0.4, home: 1.5, grid: 0.0, battery: 1.1),
      (pv: 4.2, home: 1.8, grid: 0.0, battery: -2.4),
      (pv: 8.0, home: 2.0, grid: -1.5, battery: -4.5),
      (pv: 9.2, home: 2.4, grid: -4.8, battery: -2.0),
      (pv: 7.5, home: 2.0, grid: -4.0, battery: -1.5),
      (pv: 4.5, home: 2.6, grid: -1.9, battery: 0.0),
      (pv: 1.0, home: 4.5, grid: 0.0, battery: 3.5),
      (pv: 0.0, home: 5.8, grid: 2.2, battery: 3.6),
      (pv: 0.0, home: 2.1, grid: 0.0, battery: 2.1),
      (pv: 0.0, home: 1.4, grid: 0.2, battery: 1.2),
    ]
    let readings = values.enumerated().flatMap { index, value in
      let timestamp = end.addingTimeInterval(TimeInterval(index - 12) * 2 * 60 * 60)
      return [
        HomeEnergyFlowHistory.Reading(
          series: .pvGeneration,
          timestamp: timestamp,
          kilowatts: value.pv
        ),
        HomeEnergyFlowHistory.Reading(
          series: .homeUsage,
          timestamp: timestamp,
          kilowatts: value.home
        ),
        HomeEnergyFlowHistory.Reading(
          series: .grid,
          timestamp: timestamp,
          kilowatts: value.grid
        ),
        HomeEnergyFlowHistory.Reading(
          series: .battery,
          timestamp: timestamp,
          kilowatts: value.battery
        ),
      ]
    }
    return HomeEnergyFlowHistory(
      interval: DateInterval(
        start: end.addingTimeInterval(-24 * 60 * 60),
        end: end
      ),
      readings: readings
    )
  }()

  static let denseFlowHistory: HomeEnergyFlowHistory = {
    let end = Date(timeIntervalSince1970: 1_785_408_000)
    let start = end.addingTimeInterval(-24 * 60 * 60)
    let readings = (0...720).flatMap { index in
      let timestamp = start.addingTimeInterval(TimeInterval(index) * 2 * 60)
      let hour = Double(index) / 30
      let daylightProgress = min(max((hour - 5.5) / 13, 0), 1)
      let solar = 11.5 * 4 * daylightProgress * (1 - daylightProgress)
      let backgroundUsage = 0.65 + Double((index * 37) % 18) / 100
      let usageSpike = index % 97 < 2 ? 4.2 : 0
      let home = backgroundUsage + usageSpike
      let battery: Double
      if hour < 7 {
        battery = 0.5
      } else if hour < 13 {
        battery = -min(solar * 0.72, 5.5)
      } else if hour < 18 {
        battery = -min(max(solar - home, 0), 5.5)
      } else {
        battery = index % 89 < 3 ? 5.8 : 0.6
      }
      let grid = home - solar - battery
      return [
        HomeEnergyFlowHistory.Reading(
          series: .pvGeneration,
          timestamp: timestamp,
          kilowatts: solar
        ),
        HomeEnergyFlowHistory.Reading(
          series: .homeUsage,
          timestamp: timestamp,
          kilowatts: home
        ),
        HomeEnergyFlowHistory.Reading(
          series: .grid,
          timestamp: timestamp,
          kilowatts: grid
        ),
        HomeEnergyFlowHistory.Reading(
          series: .battery,
          timestamp: timestamp,
          kilowatts: battery
        ),
      ]
    }
    return HomeEnergyFlowHistory(
      interval: DateInterval(start: start, end: end),
      readings: readings
    )
  }()

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

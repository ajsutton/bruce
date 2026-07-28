import SwiftUI

struct BrucePanelsView: View {
  @ObservedObject var temperatureStore: HomeAssistantTemperatureStore
  @ObservedObject var chargingStore: HomeAssistantEVChargingStore
  @ObservedObject var homeEnergyStore: HomeAssistantHomeEnergyStore
  let mode: BruceMode
  let isConnecting: Bool
  let connectionProblem: String?
  let manageConnection: () -> Void
  let requestHomeRefresh: () -> Void
  let isRemovingConnection: Bool

  var body: some View {
    TabView {
      Tab("Climate", systemImage: "thermometer") {
        HomeAssistantTemperatureView(
          store: temperatureStore,
          mode: mode,
          isConnecting: isConnecting,
          connectionProblem: connectionProblem,
          manageConnection: manageConnection,
          requestRefresh: requestHomeRefresh,
          isRemovingConnection: isRemovingConnection
        )
      }

      Tab("Energy", systemImage: "bolt") {
        EnergyPanelView(
          chargingStore: chargingStore,
          homeEnergyStore: homeEnergyStore,
          mode: mode,
          manageConnection: manageConnection,
          requestRefresh: requestHomeRefresh
        )
      }
    }
    .tabViewStyle(.sidebarAdaptable)
  }
}

#Preview("Panels") {
  BrucePanelsPreview.view
}

private enum BrucePanelsPreview {
  @MainActor
  static var view: some View {
    let store = HomeAssistantTemperatureStore(loader: BrucePanelsPreviewLoader())
    let chargingStore = HomeAssistantEVChargingStore(
      client: BrucePanelsPreviewEVChargingClient(),
      mode: .smart
    )
    let homeEnergyStore = HomeAssistantHomeEnergyStore(
      loader: BrucePanelsPreviewHomeEnergyLoader(),
      snapshot: HomeAssistantHomeEnergySnapshot(
        pvPowerKilowatts: 8.4,
        batteryStateOfCharge: 76,
        homeConsumptionKilowatts: 3.1,
        gridPowerKilowatts: -2.7
      ),
      isLive: true
    )
    return BrucePanelsView(
      temperatureStore: store,
      chargingStore: chargingStore,
      homeEnergyStore: homeEnergyStore,
      mode: .standard,
      isConnecting: false,
      connectionProblem: nil,
      manageConnection: {},
      requestHomeRefresh: {},
      isRemovingConnection: false
    )
    .tint(BruceMode.standard.accentColor)
    .task {
      await store.load()
    }
  }
}

private struct BrucePanelsPreviewEVChargingClient: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    .smart
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    mode
  }
}

private struct BrucePanelsPreviewHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }
}

private struct BrucePanelsPreviewLoader: HomeAssistantTemperatureLoading {
  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      continuation.yield(
        .live([
          HomeAssistantTemperatureReading(
            id: "climate.living_room",
            name: "Living Room",
            value: 23.4,
            targetValue: 22,
            unit: "°C",
            powerState: .poweredOn,
            kind: .zone,
            operatingMode: .cooling,
            icon: "mdi:sofa"
          )
        ])
      )
      continuation.finish()
    }
  }
}

import SwiftUI

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
        gridPowerKilowatts: -2.7,
        generalPriceDollarsPerKilowattHour: 0.341,
        feedInPriceDollarsPerKilowattHour: 0.127,
        importCostTodayDollars: 0.20,
        feedInEarningsTodayDollars: 0.91
      ),
      isLive: true
    )
    let garageDoorStore = HomeAssistantGarageDoorStore(
      loader: BrucePanelsPreviewGarageDoorLoader(),
      doors: [
        HomeAssistantGarageDoorSnapshot(
          id: "cover.garage",
          name: "Garage Door",
          doorState: .closed,
          lightState: .off,
          lockState: .locked
        )
      ],
      isLive: true
    )
    return BrucePanelsView(
      temperatureStore: store,
      chargingStore: chargingStore,
      garageDoorStore: garageDoorStore,
      homeEnergyStore: homeEnergyStore,
      mode: .standard,
      isConnecting: false,
      connectionProblem: nil,
      serverStatus: HomeAssistantServerStatus(
        phase: .live,
        lastSuccessfulUpdate: .now
      ),
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

private struct BrucePanelsPreviewGarageDoorLoader: HomeAssistantGarageDoorLoading {
  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] {
    []
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
  func temperatureUpdates() -> HomeAssistantTemperatureUpdateStream {
    HomeAssistantTemperatureUpdateStream { continuation in
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

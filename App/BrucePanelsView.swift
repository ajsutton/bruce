import SwiftUI

struct BrucePanelsView: View {
  @AppStorage(BrucePanel.storageKey) private var selectedPanel = BrucePanel.climate
  @ObservedObject var temperatureStore: HomeAssistantTemperatureStore
  @ObservedObject var chargingStore: HomeAssistantEVChargingStore
  @ObservedObject var garageDoorStore: HomeAssistantGarageDoorStore
  @ObservedObject var homeEnergyStore: HomeAssistantHomeEnergyStore
  let mode: BruceMode
  let isConnecting: Bool
  let connectionProblem: HomeAssistantPresentation.ConnectionProblem?
  let serverStatus: HomeAssistantServerStatus
  let manageConnection: () -> Void
  let requestHomeRefresh: () -> Void
  let isRemovingConnection: Bool

  private var copy: AppCopy {
    AppCopy(mode: mode)
  }

  private var connectionBanner: HomeAssistantConnectionBanner? {
    HomeAssistantConnectionBanner(
      presentationProblem: connectionProblem,
      serverStatus: serverStatus
    )
  }

  private var showsServerStatus: Bool {
    isRemovingConnection || isConnecting || serverStatus.phase != .idle
  }

  var body: some View {
    VStack(spacing: 0) {
      if let connectionBanner {
        HomeAssistantConnectionBannerView(
          banner: connectionBanner,
          lastSuccessfulUpdate: serverStatus.lastSuccessfulUpdate,
          mode: mode,
          manageConnection: manageConnection,
          requestRefresh: requestHomeRefresh
        )
      } else if showsServerStatus {
        HomeAssistantServerStatusView(
          mode: mode,
          status: serverStatus,
          isConnecting: isConnecting,
          isRemovingConnection: isRemovingConnection
        )
      }

      TabView(selection: $selectedPanel) {
        Tab(copy.climateTab, systemImage: "thermometer", value: BrucePanel.climate) {
          HomeAssistantTemperatureView(
            store: temperatureStore,
            mode: mode,
            isConnecting: isConnecting,
            showsConnectionProblems: connectionBanner == nil,
            requestRefresh: requestHomeRefresh
          )
        }

        Tab(copy.carTab, systemImage: "car", value: BrucePanel.car) {
          CarPanelView(
            chargingStore: chargingStore,
            garageDoorStore: garageDoorStore,
            mode: mode,
            showsConnectionProblems: connectionBanner == nil,
            manageConnection: manageConnection,
            requestRefresh: requestHomeRefresh
          )
        }

        Tab(copy.energyTab, systemImage: "bolt", value: BrucePanel.energy) {
          EnergyPanelView(
            homeEnergyStore: homeEnergyStore,
            mode: mode,
            showsConnectionProblems: connectionBanner == nil,
            manageConnection: manageConnection,
            requestRefresh: requestHomeRefresh
          )
        }
      }
      .tabViewStyle(.sidebarAdaptable)
    }
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
        gridPowerKilowatts: -2.7,
        generalPriceDollarsPerKilowattHour: 0.341,
        feedInPriceDollarsPerKilowattHour: 0.127
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

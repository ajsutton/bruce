import SwiftUI

@main
@MainActor
struct BruceUITestHostApp: App {
  @StateObject private var temperatureStore: HomeAssistantTemperatureStore
  @StateObject private var chargingStore: HomeAssistantEVChargingStore
  @StateObject private var garageDoorStore: HomeAssistantGarageDoorStore
  @StateObject private var homeEnergyStore: HomeAssistantHomeEnergyStore
  @State private var isContentReady = false

  init() {
    UserDefaults.standard.set(BrucePanel.climate.rawValue, forKey: BrucePanel.storageKey)
    HomeAssistantMaterialDesignIcon.prepare()
    _temperatureStore = StateObject(
      wrappedValue: HomeAssistantTemperatureStore(loader: UITestTemperatureLoader())
    )
    _chargingStore = StateObject(
      wrappedValue: HomeAssistantEVChargingStore(
        client: UITestEVChargingClient(),
        hasCompletedDiscovery: true
      )
    )
    _garageDoorStore = StateObject(
      wrappedValue: HomeAssistantGarageDoorStore(
        loader: UITestGarageDoorLoader(),
        hasCompletedDiscovery: true
      )
    )
    _homeEnergyStore = StateObject(
      wrappedValue: HomeAssistantHomeEnergyStore(loader: UITestHomeEnergyLoader())
    )
  }

  var body: some Scene {
    WindowGroup {
      BrucePanelsView(
        temperatureStore: temperatureStore,
        chargingStore: chargingStore,
        garageDoorStore: garageDoorStore,
        homeEnergyStore: homeEnergyStore,
        mode: .standard,
        isConnecting: false,
        connectionProblem: nil,
        serverStatus: .idle,
        manageConnection: {},
        requestHomeRefresh: {},
        isRemovingConnection: false
      )
      .tint(BruceMode.standard.accentColor)
      .overlay(alignment: .topLeading) {
        if isContentReady {
          Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier(BruceAccessibilityIdentifier.panelTestContentReady)
        }
      }
      .task {
        await temperatureStore.load()
        isContentReady = true
      }
    }
  }
}

private struct UITestTemperatureLoader: HomeAssistantTemperatureLoading {
  func temperatureUpdates() -> HomeAssistantTemperatureUpdateStream {
    HomeAssistantTemperatureUpdateStream { continuation in
      continuation.yield(
        .live(
          [
            HomeAssistantTemperatureReading(
              id: "climate.house",
              name: "House",
              value: 20.5,
              targetValue: 22,
              unit: "°C",
              powerState: .poweredOn,
              kind: .airConditioner,
              operatingMode: .cooling
            )
          ]
            + (1...8).map { number in
              HomeAssistantTemperatureReading(
                id: "sensor.room_\(number)",
                name: "Room \(number)",
                value: 20 + Double(number) / 10,
                targetValue: nil,
                unit: "°C",
                powerState: .poweredOn,
                kind: .zone,
                presetLabels: [
                  HomeAssistantClimatePresetLabel(
                    id: "area_\(number)",
                    name: "Area \(number)"
                  )
                ]
              )
            }
        )
      )
      continuation.finish()
    }
  }
}

private struct UITestEVChargingClient: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    .smart
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    mode
  }
}

private struct UITestGarageDoorLoader: HomeAssistantGarageDoorLoading {
  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] {
    []
  }
}

private struct UITestHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }
}

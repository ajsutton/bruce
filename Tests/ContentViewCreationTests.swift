import XCTest

@testable import Bruce

@MainActor
final class ContentViewCreationTests: XCTestCase {
  func testContentViewCanBeCreated() {
    #if os(macOS)
      _ = ContentView(
        modeController: BruceModeController(),
        setupStore: HomeAssistantSetupStore(discovery: ContentViewEmptyDiscovery()),
        temperatureStore: HomeAssistantTemperatureStore(
          loader: ContentViewEmptyTemperatureLoader()
        ),
        chargingStore: HomeAssistantEVChargingStore(
          client: ContentViewEVChargingClient()
        ),
        garageDoorStore: HomeAssistantGarageDoorStore(
          loader: TestGarageDoorLoader()
        ),
        homeEnergyStore: HomeAssistantHomeEnergyStore(
          loader: ContentViewHomeEnergyLoader()
        ),
        settingsNavigation: BruceSettingsNavigation()
      )
    #else
      _ = ContentView(
        modeController: BruceModeController(),
        setupStore: HomeAssistantSetupStore(discovery: ContentViewEmptyDiscovery()),
        temperatureStore: HomeAssistantTemperatureStore(
          loader: ContentViewEmptyTemperatureLoader()
        ),
        chargingStore: HomeAssistantEVChargingStore(
          client: ContentViewEVChargingClient()
        ),
        garageDoorStore: HomeAssistantGarageDoorStore(
          loader: TestGarageDoorLoader()
        ),
        homeEnergyStore: HomeAssistantHomeEnergyStore(
          loader: ContentViewHomeEnergyLoader()
        )
      )
    #endif
  }
}

private struct ContentViewHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }
}

private struct ContentViewEVChargingClient: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    .off
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    mode
  }
}

private struct ContentViewEmptyTemperatureLoader: HomeAssistantTemperatureLoading {
  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      continuation.yield(.live([]))
      continuation.finish()
    }
  }
}

private struct ContentViewEmptyDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}

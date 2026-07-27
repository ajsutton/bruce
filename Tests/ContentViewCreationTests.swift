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
        settingsNavigation: BruceSettingsNavigation()
      )
    #else
      _ = ContentView(
        modeController: BruceModeController(),
        setupStore: HomeAssistantSetupStore(discovery: ContentViewEmptyDiscovery()),
        temperatureStore: HomeAssistantTemperatureStore(
          loader: ContentViewEmptyTemperatureLoader()
        )
      )
    #endif
  }
}

private struct ContentViewEmptyTemperatureLoader: HomeAssistantTemperatureLoading {
  func loadTemperatures() async throws -> [HomeAssistantTemperatureReading] {
    []
  }
}

private struct ContentViewEmptyDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}

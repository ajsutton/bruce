import XCTest

@testable import Bruce

@MainActor
final class ContentViewCreationTests: XCTestCase {
  func testContentViewCanBeCreated() {
    #if os(macOS)
      _ = ContentView(
        modeController: BruceModeController(),
        setupStore: HomeAssistantSetupStore(discovery: ContentViewEmptyDiscovery()),
        settingsNavigation: BruceSettingsNavigation()
      )
    #else
      _ = ContentView(
        modeController: BruceModeController(),
        setupStore: HomeAssistantSetupStore(discovery: ContentViewEmptyDiscovery())
      )
    #endif
  }
}

private struct ContentViewEmptyDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}

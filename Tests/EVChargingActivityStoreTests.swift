import XCTest

@testable import Bruce

@MainActor
final class EVChargingActivityStoreTests: XCTestCase {
  func testSuccessfulLoadPublishesCurrentActivity() async {
    let client = ActivityEVChargingClient(
      loadResult: .success(
        HomeAssistantEVChargingSnapshot(
          mode: .smart,
          activity: .charging(powerWatts: 7_024)
        )
      )
    )
    let store = HomeAssistantEVChargingStore(client: client)

    await store.load()

    XCTAssertEqual(store.activity, .charging(powerWatts: 7_024))
    XCTAssertTrue(store.isActivityLive)
  }

  func testFailedLoadKeepsActivityAsLastKnown() async {
    let client = ActivityEVChargingClient(loadResult: .failure(ActivityTestError.failed))
    let store = HomeAssistantEVChargingStore(
      client: client,
      mode: .smart,
      activity: .charging(powerWatts: 7_024)
    )

    await store.load()

    XCTAssertEqual(store.activity, .charging(powerWatts: 7_024))
    XCTAssertFalse(store.isActivityLive)
    XCTAssertFalse(store.isLive)
  }

  func testModeChangeMarksPreviousActivityAsLastKnown() async {
    let client = ActivityEVChargingClient(
      loadResult: .failure(ActivityTestError.failed),
      setResult: .success(.off)
    )
    let store = HomeAssistantEVChargingStore(
      client: client,
      mode: .charging,
      activity: .charging(powerWatts: 7_024)
    )

    await store.selectMode(.off)

    XCTAssertEqual(store.mode, .off)
    XCTAssertEqual(store.activity, .charging(powerWatts: 7_024))
    XCTAssertFalse(store.isActivityLive)
  }
}

private enum ActivityTestError: Error {
  case failed
}

private actor ActivityEVChargingClient: HomeAssistantEVCharging {
  let loadResult: Result<HomeAssistantEVChargingSnapshot, ActivityTestError>
  let setResult: Result<HomeAssistantEVChargingMode, ActivityTestError>

  init(
    loadResult: Result<HomeAssistantEVChargingSnapshot, ActivityTestError>,
    setResult: Result<HomeAssistantEVChargingMode, ActivityTestError> = .failure(.failed)
  ) {
    self.loadResult = loadResult
    self.setResult = setResult
  }

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    try loadResult.get().mode
  }

  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    try loadResult.get()
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    try setResult.get()
  }
}

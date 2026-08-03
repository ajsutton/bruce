import XCTest

@testable import Bruce

@MainActor
final class HomeEnergyWidgetPublishingTests: XCTestCase {
  func testSuccessfulLoadPublishesSnapshotForTheWidget() async {
    let snapshot = HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.4,
      batteryStateOfCharge: 78,
      homeConsumptionKilowatts: 2.2,
      gridPowerKilowatts: -3.2,
      generalPriceDollarsPerKilowattHour: 0.284,
      feedInPriceDollarsPerKilowattHour: 0.08
    )
    var publishedSnapshot: HomeAssistantHomeEnergySnapshot?
    var publishedAt: Date?
    let timestamp = Date(timeIntervalSince1970: 1_000)
    let store = HomeAssistantHomeEnergyStore(
      loader: WidgetPublishingHomeEnergyLoader(snapshot: snapshot),
      publishWidgetSnapshot: { snapshot, capturedAt in
        publishedSnapshot = snapshot
        publishedAt = capturedAt
      },
      now: { timestamp }
    )

    await store.load()

    XCTAssertEqual(publishedSnapshot, snapshot)
    XCTAssertEqual(publishedAt, timestamp)
  }
}

private actor WidgetPublishingHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  let snapshot: HomeAssistantHomeEnergySnapshot

  init(snapshot: HomeAssistantHomeEnergySnapshot) {
    self.snapshot = snapshot
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    snapshot
  }
}

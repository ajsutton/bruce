import XCTest

final class EnergyWidgetRefreshReconciliationTests: XCTestCase {
  func testFailedRefreshUsesNewerConcurrentAppSnapshotAsCurrent() throws {
    let suiteName = "BruceEnergyWidgetTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = try XCTUnwrap(HomeEnergyWidgetSnapshotStore(defaults: defaults))
    let cached = snapshot(capturedAt: Date(timeIntervalSince1970: 1_000))
    let appPublication = snapshot(capturedAt: Date(timeIntervalSince1970: 2_000))
    try store.save(cached, writer: .widget)

    try store.save(appPublication, writer: .app)
    let result = EnergyWidgetRefreshReconciliation.afterFailure(
      cachedSnapshot: cached,
      sourceIdentifier: cached.sourceIdentifier,
      store: store
    )

    XCTAssertEqual(result, .current(appPublication))
  }

  func testMissingCredentialsCannotPromoteCachedSnapshotToCurrent() throws {
    let suiteName = "BruceEnergyWidgetTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = try XCTUnwrap(HomeEnergyWidgetSnapshotStore(defaults: defaults))
    let newerOldHomeSnapshot = snapshot(capturedAt: Date(timeIntervalSince1970: 2_000))
    try store.save(newerOldHomeSnapshot, writer: .app)

    let result = EnergyWidgetRefreshReconciliation.afterFailure(
      cachedSnapshot: nil,
      sourceIdentifier: nil,
      store: store
    )

    XCTAssertEqual(result, .lastKnown(nil))
  }

  private func snapshot(capturedAt: Date) -> HomeEnergyWidgetSnapshot {
    HomeEnergyWidgetSnapshot(
      sourceIdentifier: "test-source",
      capturedAt: capturedAt,
      pvPowerKilowatts: 6.4,
      batteryStateOfCharge: 78,
      homeConsumptionKilowatts: 2.2,
      gridPowerKilowatts: -3.2,
      generalPriceDollarsPerKilowattHour: 0.284,
      feedInPriceDollarsPerKilowattHour: 0.08,
      importCostTodayDollars: 2.43,
      feedInEarningsTodayDollars: 4.19
    )
  }
}

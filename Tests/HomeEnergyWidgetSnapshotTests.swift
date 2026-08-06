import XCTest

@testable import Bruce

@MainActor
final class HomeEnergyWidgetSnapshotTests: XCTestCase {
  func testSnapshotUsesThePrecisionDisplayedByTheWidget() {
    let capturedAt = Date(timeIntervalSince1970: 1_000)
    let snapshot = HomeEnergyWidgetSnapshot(
      snapshot: HomeAssistantHomeEnergySnapshot(
        pvPowerKilowatts: 6.44,
        batteryStateOfCharge: 78.4,
        homeConsumptionKilowatts: 2.16,
        gridPowerKilowatts: -3.24,
        generalPriceDollarsPerKilowattHour: 0.284_4,
        feedInPriceDollarsPerKilowattHour: 0.080_4,
        importCostTodayDollars: 2.434,
        feedInEarningsTodayDollars: 4.186
      ),
      capturedAt: capturedAt
    )

    XCTAssertEqual(snapshot.capturedAt, capturedAt)
    XCTAssertEqual(snapshot.pvPowerKilowatts, 6.4)
    XCTAssertEqual(snapshot.batteryStateOfCharge, 78)
    XCTAssertEqual(snapshot.homeConsumptionKilowatts, 2.2)
    XCTAssertEqual(snapshot.gridPowerKilowatts, -3.2)
    XCTAssertEqual(snapshot.generalPriceDollarsPerKilowattHour, 0.284)
    XCTAssertEqual(snapshot.feedInPriceDollarsPerKilowattHour, 0.08)
    XCTAssertEqual(snapshot.importCostTodayDollars, 2.43)
    XCTAssertEqual(snapshot.feedInEarningsTodayDollars, 4.19)
    XCTAssertTrue(snapshot.importCostIsCurrent)
    XCTAssertTrue(snapshot.feedInEarningsIsCurrent)
  }

  func testSnapshotPreservesFailedDailyTotalFreshness() {
    let previous = makeSnapshot(capturedAt: Date(timeIntervalSince1970: 1_000))
    let snapshot = HomeEnergyWidgetSnapshot(
      snapshot: HomeAssistantHomeEnergySnapshot(
        pvPowerKilowatts: 6.4,
        batteryStateOfCharge: 78,
        homeConsumptionKilowatts: 2.1,
        gridPowerKilowatts: -3.2,
        generalPriceDollarsPerKilowattHour: 0.284,
        feedInPriceDollarsPerKilowattHour: 0.08,
        importCostTodayDollars: nil,
        feedInEarningsTodayDollars: nil,
        importCostTodayStatus: .failed,
        feedInEarningsTodayStatus: .failed
      ),
      capturedAt: Date(timeIntervalSince1970: 2_000),
      previous: previous
    )

    XCTAssertFalse(snapshot.importCostIsCurrent)
    XCTAssertFalse(snapshot.feedInEarningsIsCurrent)
    XCTAssertEqual(snapshot.importCostTodayDollars, previous.importCostTodayDollars)
    XCTAssertEqual(snapshot.feedInEarningsTodayDollars, previous.feedInEarningsTodayDollars)
    XCTAssertEqual(snapshot.importCostCapturedAt, previous.importCostCapturedAt)
    XCTAssertEqual(snapshot.feedInEarningsCapturedAt, previous.feedInEarningsCapturedAt)
  }

  func testSnapshotDoesNotCarryFailedDailyTotalsAcrossMidnight() throws {
    let calendar = Calendar(identifier: .gregorian)
    let previousDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 23, minute: 59))
    )
    let capturedAt = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, minute: 1))
    )
    let snapshot = HomeEnergyWidgetSnapshot(
      snapshot: HomeAssistantHomeEnergySnapshot(
        pvPowerKilowatts: nil,
        batteryStateOfCharge: nil,
        homeConsumptionKilowatts: nil,
        gridPowerKilowatts: nil,
        generalPriceDollarsPerKilowattHour: nil,
        feedInPriceDollarsPerKilowattHour: nil,
        importCostTodayDollars: 2.43,
        feedInEarningsTodayDollars: 4.18,
        importCostTodayStatus: .failed,
        feedInEarningsTodayStatus: .failed
      ),
      capturedAt: capturedAt,
      previous: makeSnapshot(capturedAt: previousDate)
    )

    XCTAssertNil(snapshot.importCostTodayDollars)
    XCTAssertNil(snapshot.feedInEarningsTodayDollars)
  }

  func testSnapshotUsesHomeAssistantIntervalInsteadOfDeviceCalendar() {
    let previousAt = Date(timeIntervalSince1970: 900)
    let capturedAt = Date(timeIntervalSince1970: 1_000)
    let previous = HomeEnergyWidgetSnapshot(
      sourceIdentifier: "test",
      capturedAt: previousAt,
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil,
      importCostTodayDollars: 2.43,
      feedInEarningsTodayDollars: 4.18,
      dailyEnergyInterval: DateInterval(
        start: Date(timeIntervalSince1970: 0),
        end: Date(timeIntervalSince1970: 1_000)
      )
    )
    let snapshot = HomeEnergyWidgetSnapshot(
      snapshot: HomeAssistantHomeEnergySnapshot(
        pvPowerKilowatts: nil,
        batteryStateOfCharge: 50,
        homeConsumptionKilowatts: nil,
        gridPowerKilowatts: nil,
        generalPriceDollarsPerKilowattHour: nil,
        feedInPriceDollarsPerKilowattHour: nil,
        importCostTodayStatus: .failed,
        feedInEarningsTodayStatus: .failed
      ),
      capturedAt: capturedAt,
      previous: previous
    )

    XCTAssertNil(snapshot.importCostTodayDollars)
    XCTAssertNil(snapshot.feedInEarningsTodayDollars)
  }

  func testStoreRoundTripsSnapshotInSharedDefaults() throws {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = try XCTUnwrap(HomeEnergyWidgetSnapshotStore(defaults: defaults))
    let snapshot = makeSnapshot(capturedAt: Date(timeIntervalSince1970: 2_000))

    try store.save(snapshot, writer: .app)

    XCTAssertEqual(try store.load(), snapshot)
  }

  func testStoreKeepsTheNewestSnapshotAcrossAppAndWidgetWriters() throws {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = try XCTUnwrap(HomeEnergyWidgetSnapshotStore(defaults: defaults))
    let newer = makeSnapshot(capturedAt: Date(timeIntervalSince1970: 2_000))
    let older = makeSnapshot(capturedAt: Date(timeIntervalSince1970: 1_000))

    try store.save(newer, writer: .app)
    let selectedSnapshot = try store.saveAndLoadNewest(older, writer: .widget)

    XCTAssertEqual(try store.load(), newer)
    XCTAssertEqual(selectedSnapshot, newer)
  }

  func testStoreFindsNewerAppSnapshotAfterWidgetRefreshStarts() throws {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = try XCTUnwrap(HomeEnergyWidgetSnapshotStore(defaults: defaults))
    let cached = makeSnapshot(capturedAt: Date(timeIntervalSince1970: 1_000))
    let appPublication = makeSnapshot(capturedAt: Date(timeIntervalSince1970: 2_000))
    try store.save(cached, writer: .widget)

    try store.save(appPublication, writer: .app)

    XCTAssertEqual(
      try store.loadNewer(than: cached, sourceIdentifier: cached.sourceIdentifier),
      appPublication
    )
  }

  func testStoreOnlyReturnsSnapshotsForTheConnectedHome() throws {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = try XCTUnwrap(HomeEnergyWidgetSnapshotStore(defaults: defaults))
    let oldHome = makeSnapshot(capturedAt: Date(timeIntervalSince1970: 2_000))

    try store.save(oldHome, writer: .app)

    XCTAssertNil(try store.load(sourceIdentifier: "another-home"))
    XCTAssertEqual(try store.load(sourceIdentifier: oldHome.sourceIdentifier), oldHome)
  }

  func testStoreReportsCorruptSnapshots() throws {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = try XCTUnwrap(HomeEnergyWidgetSnapshotStore(defaults: defaults))
    defaults.set(Data("not-json".utf8), forKey: "homeEnergyWidgetSnapshot.app")

    XCTAssertThrowsError(try store.load())
  }

  func testStoreLoadsAppSnapshotWhenWidgetSnapshotIsNewer() throws {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = try XCTUnwrap(HomeEnergyWidgetSnapshotStore(defaults: defaults))
    let appSnapshot = makeSnapshot(capturedAt: Date(timeIntervalSince1970: 1_000))
    let widgetSnapshot = makeSnapshot(capturedAt: Date(timeIntervalSince1970: 2_000))
    try store.save(appSnapshot, writer: .app)
    try store.save(widgetSnapshot, writer: .widget)

    XCTAssertEqual(
      try store.load(writer: .app, sourceIdentifier: appSnapshot.sourceIdentifier),
      appSnapshot
    )
    XCTAssertEqual(try store.load(), widgetSnapshot)
  }

  func testPublisherReloadsOnlyWhenDisplayedReadingsChange() throws {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = try XCTUnwrap(HomeEnergyWidgetSnapshotStore(defaults: defaults))
    var reloadCount = 0
    let publisher = HomeEnergyWidgetSnapshotPublisher(
      store: store,
      sourceIdentifier: { "test" },
      reloadTimelines: { reloadCount += 1 }
    )
    let snapshot = HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 6.4,
      batteryStateOfCharge: 78,
      homeConsumptionKilowatts: 2.2,
      gridPowerKilowatts: -3.2,
      generalPriceDollarsPerKilowattHour: 0.284,
      feedInPriceDollarsPerKilowattHour: 0.08,
      importCostTodayDollars: 2.43,
      feedInEarningsTodayDollars: 4.19
    )

    publisher.publish(snapshot, capturedAt: Date(timeIntervalSince1970: 1_000))
    publisher.publish(snapshot, capturedAt: Date(timeIntervalSince1970: 2_000))

    XCTAssertEqual(reloadCount, 1)
    XCTAssertEqual(try store.load()?.capturedAt, Date(timeIntervalSince1970: 2_000))
  }

  private func makeSnapshot(capturedAt: Date) -> HomeEnergyWidgetSnapshot {
    HomeEnergyWidgetSnapshot(
      capturedAt: capturedAt,
      pvPowerKilowatts: 6.4,
      batteryStateOfCharge: 78,
      homeConsumptionKilowatts: 2.2,
      gridPowerKilowatts: -3.2,
      generalPriceDollarsPerKilowattHour: 0.284,
      feedInPriceDollarsPerKilowattHour: 0.08,
      importCostTodayDollars: 2.43,
      feedInEarningsTodayDollars: 4.19,
      dailyEnergyInterval: Calendar(identifier: .gregorian).dateInterval(
        of: .day,
        for: capturedAt
      )
    )
  }
}

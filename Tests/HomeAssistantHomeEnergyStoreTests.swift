import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantHomeEnergyStoreTests: XCTestCase {
  func testSnapshotPresentationEquivalenceMatchesVisiblePrecisionAndStates() {
    let snapshot = HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.41,
      batteryStateOfCharge: 49.4,
      homeConsumptionKilowatts: 3.11,
      gridPowerKilowatts: -0.06,
      generalPriceDollarsPerKilowattHour: 0.341_1,
      feedInPriceDollarsPerKilowattHour: 0.127_1
    )
    let visiblyIdentical = HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.44,
      batteryStateOfCharge: 49.49,
      homeConsumptionKilowatts: 3.14,
      gridPowerKilowatts: 0.06,
      generalPriceDollarsPerKilowattHour: 0.341_4,
      feedInPriceDollarsPerKilowattHour: 0.127_4
    )
    let changedGridState = HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.44,
      batteryStateOfCharge: 49.49,
      homeConsumptionKilowatts: 3.14,
      gridPowerKilowatts: -0.14,
      generalPriceDollarsPerKilowattHour: 0.341_4,
      feedInPriceDollarsPerKilowattHour: 0.127_4
    )

    XCTAssertTrue(snapshot.hasSamePresentation(as: visiblyIdentical))
    XCTAssertFalse(snapshot.hasSamePresentation(as: changedGridState))
  }

  func testSnapshotPresentationEquivalenceUsesFormatterTieRounding() {
    let snapshot = presentationSnapshot(
      solarPower: 8.45,
      battery: 48.5,
      consumption: 3.25,
      grid: -2.25,
      generalPrice: 0.340_5,
      feedInPrice: 0.127_5
    )

    XCTAssertFalse(
      snapshot.hasSamePresentation(as: presentationSnapshot(solarPower: 8.46))
    )
    XCTAssertFalse(
      snapshot.hasSamePresentation(as: presentationSnapshot(battery: 48.6))
    )
    XCTAssertFalse(
      snapshot.hasSamePresentation(as: presentationSnapshot(consumption: 3.26))
    )
    XCTAssertFalse(
      snapshot.hasSamePresentation(as: presentationSnapshot(grid: -2.26))
    )
    XCTAssertFalse(
      snapshot.hasSamePresentation(as: presentationSnapshot(generalPrice: 0.340_49))
    )
    XCTAssertFalse(
      snapshot.hasSamePresentation(as: presentationSnapshot(feedInPrice: 0.127_4))
    )
    XCTAssertFalse(
      presentationSnapshot(generalPrice: 0.084_49)
        .hasSamePresentation(as: presentationSnapshot(generalPrice: 0.084_5))
    )
    XCTAssertFalse(
      presentationSnapshot(feedInPrice: 0.084_49)
        .hasSamePresentation(as: presentationSnapshot(feedInPrice: 0.084_5))
    )
  }

  func testSnapshotPresentationEquivalencePreservesSemanticBands() {
    for (lower, upper) in [(19.9, 20.0), (24.9, 25.0), (49.9, 50.0), (74.9, 75.0)] {
      XCTAssertFalse(
        presentationSnapshot(battery: lower)
          .hasSamePresentation(as: presentationSnapshot(battery: upper))
      )
    }
    XCTAssertFalse(
      presentationSnapshot(grid: 0.09)
        .hasSamePresentation(as: presentationSnapshot(grid: 0.1))
    )
    XCTAssertFalse(
      presentationSnapshot(grid: -0.09)
        .hasSamePresentation(as: presentationSnapshot(grid: -0.1))
    )
    XCTAssertFalse(
      presentationSnapshot(feedInPrice: 0.000_1)
        .hasSamePresentation(as: presentationSnapshot(feedInPrice: -0.000_1))
    )
  }

  func testSnapshotPresentationEquivalencePublishesVisibleCurrencyChangesOnly() {
    let snapshot = presentationSnapshot(
      importCostToday: 0.201,
      feedInEarningsToday: 0.911
    )

    XCTAssertTrue(
      snapshot.hasSamePresentation(
        as: presentationSnapshot(
          importCostToday: 0.204,
          feedInEarningsToday: 0.914
        )
      )
    )
    XCTAssertFalse(
      snapshot.hasSamePresentation(
        as: presentationSnapshot(
          importCostToday: 0.206,
          feedInEarningsToday: 0.916
        )
      )
    )
  }

  func testSuccessfulLoadPublishesLiveSnapshot() async {
    let snapshot = makeSnapshot(solarPower: 8.4)
    let store = HomeAssistantHomeEnergyStore(
      loader: ImmediateHomeEnergyLoader(result: .success(snapshot))
    )

    await store.load()

    XCTAssertEqual(store.snapshot, snapshot)
    XCTAssertTrue(store.isLive)
    XCTAssertFalse(store.isLoading)
  }

  func testSnapshotWithoutAnyReadingsPreservesLastKnownSnapshot() async {
    let snapshot = makeSnapshot(solarPower: 8.4)
    let store = HomeAssistantHomeEnergyStore(
      loader: ImmediateHomeEnergyLoader(result: .success(.unavailable)),
      snapshot: snapshot,
      isLive: true
    )

    await store.load()

    XCTAssertEqual(store.snapshot, snapshot)
    XCTAssertFalse(store.isLive)
    XCTAssertEqual(store.problem, .invalidResponse)
  }

  func testFailedLoadPreservesLastKnownSnapshot() async {
    let snapshot = makeSnapshot(solarPower: 8.4)
    let store = HomeAssistantHomeEnergyStore(
      loader: ImmediateHomeEnergyLoader(result: .failure(HomeEnergyTestError.failed)),
      snapshot: snapshot,
      isLive: true
    )

    await store.load()

    XCTAssertEqual(store.snapshot, snapshot)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.isLoading)
    XCTAssertEqual(store.problem, .invalidResponse)
  }

  func testNewLoadReplacesPendingLoad() async {
    let loader = ControlledHomeEnergyLoader(requestCount: 2)
    let store = HomeAssistantHomeEnergyStore(loader: loader)
    let firstLoad = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    let secondLoad = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 1)], timeout: 1)

    loader.succeed(1, with: makeSnapshot(solarPower: 9.1))
    await secondLoad.value
    loader.succeed(0, with: makeSnapshot(solarPower: 1.2))
    await firstLoad.value

    XCTAssertEqual(store.snapshot.pvPowerKilowatts, 9.1)
    XCTAssertTrue(store.isLive)
  }

  func testCancelledLoadCannotPublishItsSnapshot() async {
    let initial = makeSnapshot(solarPower: 4.2)
    let loader = ControlledHomeEnergyLoader(requestCount: 1)
    let store = HomeAssistantHomeEnergyStore(
      loader: loader,
      snapshot: initial,
      isLive: true
    )
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)

    load.cancel()
    loader.succeed(0, with: makeSnapshot(solarPower: 9.1))
    await load.value

    XCTAssertEqual(store.snapshot, initial)
    XCTAssertFalse(store.isLive)
  }

  func testDisconnectClearsReadings() {
    let store = HomeAssistantHomeEnergyStore(
      loader: ImmediateHomeEnergyLoader(result: .success(.unavailable)),
      snapshot: makeSnapshot(solarPower: 8.4),
      isLive: true
    )

    store.reset()

    XCTAssertEqual(store.snapshot, .unavailable)
    XCTAssertFalse(store.isLive)
  }

  func testAuthenticationFailureRequestsSignIn() async {
    var requiresAuthentication = false
    let store = HomeAssistantHomeEnergyStore(
      loader: AuthenticationFailureHomeEnergyLoader(),
      onAuthenticationRequired: {
        requiresAuthentication = true
      }
    )

    await store.load()

    XCTAssertEqual(store.problem, .signInRequired)
    XCTAssertTrue(requiresAuthentication)

    await store.synchronize(with: .unavailable)

    XCTAssertEqual(store.problem, .signInRequired)
  }

  func testUnavailableConnectionRequiresConnectionManagement() async {
    let store = HomeAssistantHomeEnergyStore(
      loader: ImmediateHomeEnergyLoader(result: .success(.unavailable))
    )

    await store.synchronize(with: .unavailable)

    XCTAssertEqual(store.problem, .connectionNeedsManagement)
    XCTAssertTrue(store.problem?.needsConnectionManagement == true)
  }

  private func makeSnapshot(solarPower: Double) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: solarPower,
      batteryStateOfCharge: 76,
      homeConsumptionKilowatts: 3.1,
      gridPowerKilowatts: -2.7,
      generalPriceDollarsPerKilowattHour: 0.341,
      feedInPriceDollarsPerKilowattHour: 0.127
    )
  }

  private func presentationSnapshot(
    solarPower: Double = 8.45,
    battery: Double = 48.5,
    consumption: Double = 3.25,
    grid: Double = -2.25,
    generalPrice: Double = 0.340_5,
    feedInPrice: Double = 0.127_5,
    importCostToday: Double? = nil,
    feedInEarningsToday: Double? = nil
  ) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: solarPower,
      batteryStateOfCharge: battery,
      homeConsumptionKilowatts: consumption,
      gridPowerKilowatts: grid,
      generalPriceDollarsPerKilowattHour: generalPrice,
      feedInPriceDollarsPerKilowattHour: feedInPrice,
      importCostTodayDollars: importCostToday,
      feedInEarningsTodayDollars: feedInEarningsToday
    )
  }
}

private actor AuthenticationFailureHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw HomeAssistantAPIError.unauthorized
  }
}

private enum HomeEnergyTestError: Error {
  case failed
}

private actor ImmediateHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  let result: Result<HomeAssistantHomeEnergySnapshot, HomeEnergyTestError>

  init(result: Result<HomeAssistantHomeEnergySnapshot, HomeEnergyTestError>) {
    self.result = result
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    try result.get()
  }
}

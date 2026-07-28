import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantHomeEnergyStoreTests: XCTestCase {
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
      gridPowerKilowatts: -2.7
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

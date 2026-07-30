import Combine
import XCTest

@testable import Bruce

@MainActor
final class BatteryHistoryStreamLifecycleTests: XCTestCase {
  func testRefreshRetriesBatteryHistoryAfterAnInitialFailure() async {
    let timestamp = Date(timeIntervalSince1970: 500_000)
    let dates = ControlledHomeEnergyDateSequence([timestamp])
    let loader = ControlledBatteryHistoryLoader(
      batteryRequestCount: 2,
      providesContinuousEnergyUpdates: true
    )
    let store = HomeAssistantHomeEnergyStore(loader: loader, now: dates.next)
    let synchronization = Task {
      await store.synchronize(with: .connected(credentials()))
    }
    await fulfillment(
      of: [loader.updateStreamStarted, loader.batteryStarted(at: 0)],
      timeout: 1
    )
    await failBatteryLoad(0, on: store, loader: loader)

    loader.yield(.refreshing(snapshot(charge: 43)))
    loader.yield(.live(snapshot(charge: 43)))
    await fulfillment(
      of: [dates.requested(at: 0), loader.batteryStarted(at: 1)],
      timeout: 1
    )
    await completeBatteryLoad(
      1,
      on: store,
      loader: loader,
      history: history(endingAt: timestamp.addingTimeInterval(-10), charge: 34)
    )

    XCTAssertEqual(
      store.batteryHistoryStore.batteryHistory.readings.compactMap(
        \.stateOfCharge
      ),
      [34, 43]
    )
    XCTAssertNil(store.batteryHistoryStore.problem)
    await stop(synchronization, loader: loader)
  }

  func testStreamTerminationMarksLoadedBatteryHistoryStale() async {
    let timestamp = Date(timeIntervalSince1970: 600_000)
    let loader = ControlledBatteryHistoryLoader(
      batteryRequestCount: 1,
      providesContinuousEnergyUpdates: true
    )
    let store = HomeAssistantHomeEnergyStore(loader: loader)
    let synchronization = Task {
      await store.synchronize(with: .connected(credentials()))
    }
    await fulfillment(
      of: [loader.updateStreamStarted, loader.batteryStarted(at: 0)],
      timeout: 1
    )
    await completeBatteryLoad(
      0,
      on: store,
      loader: loader,
      history: history(endingAt: timestamp, charge: 34)
    )

    loader.finishUpdates()
    await synchronization.value

    XCTAssertTrue(store.batteryHistoryStore.isStale)
    XCTAssertEqual(store.problem, .connectionUnavailable)
  }

  private func failBatteryLoad(
    _ request: Int,
    on store: HomeAssistantHomeEnergyStore,
    loader: ControlledBatteryHistoryLoader
  ) async {
    let completion = loadCompletion(for: store.batteryHistoryStore)
    loader.failBattery(request, with: BatteryStreamLifecycleError.failed)
    await fulfillment(of: [completion.expectation], timeout: 1)
    XCTAssertEqual(store.batteryHistoryStore.problem, .loadFailed)
    withExtendedLifetime(completion.subscription) {}
  }

  private func completeBatteryLoad(
    _ request: Int,
    on store: HomeAssistantHomeEnergyStore,
    loader: ControlledBatteryHistoryLoader,
    history: HomeEnergyBatteryHistory
  ) async {
    let completion = loadCompletion(for: store.batteryHistoryStore)
    loader.succeedBattery(request, with: history)
    await fulfillment(of: [completion.expectation], timeout: 1)
    withExtendedLifetime(completion.subscription) {}
  }

  private func loadCompletion(
    for store: HomeEnergyBatteryHistoryStore
  ) -> (expectation: XCTestExpectation, subscription: AnyCancellable) {
    let expectation = expectation(description: "Battery history load completed")
    let subscription = store.$isLoading
      .dropFirst()
      .filter { !$0 }
      .prefix(1)
      .sink { _ in expectation.fulfill() }
    return (expectation, subscription)
  }

  private func stop(
    _ synchronization: Task<Void, Never>,
    loader: ControlledBatteryHistoryLoader
  ) async {
    synchronization.cancel()
    loader.finishUpdates()
    await synchronization.value
  }

  private func history(
    endingAt end: Date,
    charge: Double
  ) -> HomeEnergyBatteryHistory {
    let start = end.addingTimeInterval(-24 * 60 * 60)
    return HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, end: end),
      readings: [.init(timestamp: start, stateOfCharge: charge)]
    )
  }

  private func snapshot(charge: Double) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.4,
      batteryStateOfCharge: charge,
      homeConsumptionKilowatts: 3.1,
      gridPowerKilowatts: -2.7,
      generalPriceDollarsPerKilowattHour: 0.22,
      feedInPriceDollarsPerKilowattHour: 0.07
    )
  }

  private func credentials() -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

private enum BatteryStreamLifecycleError: Error {
  case failed
}

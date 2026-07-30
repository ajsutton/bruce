import Combine
import XCTest

@testable import Bruce

@MainActor
final class BatteryHistoryIntegrationTests: XCTestCase {
  func testAuthenticationFailureInvalidatesSiblingHistoryRequest() async {
    var requiresAuthentication = false
    let loader = ControlledBatteryHistoryLoader(
      batteryRequestCount: 1,
      priceRequestCount: 1
    )
    let store = HomeAssistantHomeEnergyStore(
      loader: loader,
      onAuthenticationRequired: {
        requiresAuthentication = true
      }
    )
    store.reloadHistory()
    await fulfillment(
      of: [
        loader.batteryStarted(at: 0),
        loader.priceStarted(at: 0),
      ],
      timeout: 1
    )
    let problem = parentProblemCompletion(for: store)

    loader.failBattery(0, with: HomeAssistantAPIError.unauthorized)
    await fulfillment(of: [problem.expectation], timeout: 1)

    XCTAssertTrue(requiresAuthentication)
    XCTAssertFalse(store.batteryHistoryStore.isLoading)
    XCTAssertFalse(store.priceHistoryStore.isLoading)
    XCTAssertEqual(store.priceHistoryStore.priceHistory, .empty)

    loader.succeedPrice(0, with: priceHistory())
    await fulfillment(of: [loader.priceFinished(at: 0)], timeout: 1)

    XCTAssertEqual(store.priceHistoryStore.priceHistory, .empty)
    XCTAssertFalse(store.priceHistoryStore.hasUsableHistory)
    withExtendedLifetime(problem.subscription) {}
  }

  func testReconnectReloadsBatteryHistoryAndMergesLiveCharge() async {
    let start = Date(timeIntervalSince1970: 400_000)
    let initialEnd = start.addingTimeInterval(24 * 60 * 60)
    let liveTimestamp = initialEnd.addingTimeInterval(60)
    let dates = ControlledHomeEnergyDateSequence([liveTimestamp])
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
    await completeBatteryLoad(
      0,
      on: store,
      loader: loader,
      history: batteryHistory(
        start: start,
        end: initialEnd,
        charge: 34
      )
    )

    loader.yield(.reconnecting(store.snapshot))
    loader.yield(.live(snapshot(charge: 43)))
    await fulfillment(
      of: [dates.requested(at: 0), loader.batteryStarted(at: 1)],
      timeout: 1
    )
    await completeBatteryLoad(
      1,
      on: store,
      loader: loader,
      history: recoveredHistory(
        start: start,
        initialEnd: initialEnd,
        liveTimestamp: liveTimestamp
      )
    )

    XCTAssertEqual(
      store.batteryHistoryStore.batteryHistory.readings.compactMap(
        \.stateOfCharge
      ),
      [34, 40, 43]
    )
    XCTAssertFalse(store.batteryHistoryStore.isStale)
    await stop(synchronization, loader: loader)
  }

  func testOverflowMarkedUpdateBackfillsDroppedBatteryTransitions() async {
    let start = Date(timeIntervalSince1970: 500_000)
    let initialEnd = start.addingTimeInterval(24 * 60 * 60)
    let liveTimestamp = initialEnd.addingTimeInterval(60)
    let dates = ControlledHomeEnergyDateSequence([liveTimestamp])
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
    await completeBatteryLoad(
      0,
      on: store,
      loader: loader,
      history: batteryHistory(
        start: start,
        end: initialEnd,
        charge: 34
      )
    )

    loader.yield(.live(snapshot(charge: 43).requiringHistoryBackfill()))
    await fulfillment(
      of: [dates.requested(at: 0), loader.batteryStarted(at: 1)],
      timeout: 1
    )
    await completeBatteryLoad(
      1,
      on: store,
      loader: loader,
      history: recoveredHistory(
        start: start,
        initialEnd: initialEnd,
        liveTimestamp: liveTimestamp
      )
    )

    XCTAssertEqual(
      store.batteryHistoryStore.batteryHistory.readings.compactMap(
        \.stateOfCharge
      ),
      [34, 40, 43]
    )
    XCTAssertFalse(store.batteryHistoryStore.isStale)
    await stop(synchronization, loader: loader)
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

  private func parentProblemCompletion(
    for store: HomeAssistantHomeEnergyStore
  ) -> (expectation: XCTestExpectation, subscription: AnyCancellable) {
    let expectation = expectation(description: "History authentication failed")
    let subscription = store.$problem
      .compactMap { $0 }
      .filter { $0 == .signInRequired }
      .prefix(1)
      .sink { _ in expectation.fulfill() }
    return (expectation, subscription)
  }

  private func batteryHistory(
    start: Date,
    end: Date,
    charge: Double
  ) -> HomeEnergyBatteryHistory {
    HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, end: end),
      readings: [.init(timestamp: start, stateOfCharge: charge)]
    )
  }

  private func recoveredHistory(
    start: Date,
    initialEnd: Date,
    liveTimestamp: Date
  ) -> HomeEnergyBatteryHistory {
    HomeEnergyBatteryHistory(
      interval: DateInterval(
        start: start,
        end: liveTimestamp.addingTimeInterval(-10)
      ),
      readings: [
        .init(timestamp: start, stateOfCharge: 34),
        .init(
          timestamp: initialEnd.addingTimeInterval(30),
          stateOfCharge: 40
        ),
      ]
    )
  }

  private func priceHistory() -> HomeEnergyPriceHistory {
    let start = Date(timeIntervalSince1970: 100_000)
    return HomeEnergyPriceHistory(
      interval: DateInterval(start: start, duration: 24 * 60 * 60),
      readings: [
        .init(tariff: .general, timestamp: start, dollarsPerKilowattHour: 0.22),
        .init(tariff: .feedIn, timestamp: start, dollarsPerKilowattHour: 0.07),
      ]
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

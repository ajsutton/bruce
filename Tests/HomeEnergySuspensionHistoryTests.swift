import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeEnergySuspensionHistoryTests: XCTestCase {
  func testShortSuspensionReusesHistoryWithoutRemoteReload() async {
    let now = Date(timeIntervalSince1970: 500_000)
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = makeStoreWithHistory(loader: loader, now: now)
    store.canReuseHistoryAfterSuspension = true
    let deadline = now.addingTimeInterval(HomeEnergyHistorySampling.interval)
    let synchronization = Task {
      await store.synchronize(with: .ready(credentials()), historyReuseDeadline: deadline)
    }
    await fulfillment(of: [loader.updateStreamStarted], timeout: 1)

    store.prepareForActivitySuspension()
    store.resumeAfterActivitySuspension(historyReuseDeadline: deadline)
    let live = liveCompletion(for: store)
    loader.yield(.reconnecting(store.snapshot))
    loader.yield(.live(snapshot(general: 0.32, feedIn: 0.1)))
    await fulfillment(of: [live.expectation], timeout: 1)

    XCTAssertEqual(loader.historyRequestCount, 0)
    if loader.historyRequestCount > 0 {
      loader.failHistory(0, with: CancellationError())
    }
    withExtendedLifetime(live.subscription) {}
    await stop(synchronization, loader: loader)
  }

  func testLongSuspensionDefersOneRemoteReloadUntilLive() async {
    let now = Date(timeIntervalSince1970: 600_000)
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 2)
    let store = HomeAssistantHomeEnergyStore(loader: loader, now: { now })
    let synchronization = Task { await store.synchronize(with: .ready(credentials())) }
    await waitForInitialRequests(loader)
    loader.yield(.live(snapshot(general: 0.31, feedIn: 0.09)))
    await completeInitialHistory(on: store, loader: loader, now: now)

    store.prepareForActivitySuspension()
    store.resumeAfterActivitySuspension(historyReuseDeadline: nil)
    loader.yield(.reconnecting(store.snapshot))
    XCTAssertEqual(loader.historyRequestCount, 1)
    loader.yield(.live(snapshot(general: 0.32, feedIn: 0.1)))
    await fulfillment(of: [loader.historyStarted(at: 1)], timeout: 1)

    XCTAssertEqual(loader.historyRequestCount, 2)
    loader.failHistory(1, with: CancellationError())
    await stop(synchronization, loader: loader)
  }

  func testReadyWhileSuspendedDefersInitialHistoryLoadUntilLive() async {
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = HomeAssistantHomeEnergyStore(loader: loader)
    store.prepareForActivitySuspension()
    store.resumeAfterActivitySuspension(historyReuseDeadline: nil)
    let synchronization = Task { await store.synchronize(with: .ready(credentials())) }
    await fulfillment(of: [loader.updateStreamStarted], timeout: 1)

    XCTAssertEqual(loader.historyRequestCount, 0)
    loader.yield(.live(snapshot(general: 0.31, feedIn: 0.09)))
    await fulfillment(of: [loader.historyStarted(at: 0)], timeout: 1)

    XCTAssertEqual(loader.historyRequestCount, 1)
    loader.failHistory(0, with: CancellationError())
    await stop(synchronization, loader: loader)
  }

  private func completeInitialHistory(
    on store: HomeAssistantHomeEnergyStore,
    loader: ControlledHomeEnergyHistoryLoader,
    now: Date
  ) async {
    let completion = historyCompletion(for: store)
    loader.succeedHistory(0, with: history(endingAt: now))
    await fulfillment(of: [completion.expectation], timeout: 1)
    withExtendedLifetime(completion.subscription) {}
  }

  private func makeStoreWithHistory(
    loader: ControlledHomeEnergyHistoryLoader,
    now: Date
  ) -> HomeAssistantHomeEnergyStore {
    let interval = DateInterval(start: now.addingTimeInterval(-60), end: now)
    return HomeAssistantHomeEnergyStore(
      loader: loader,
      snapshot: snapshot(general: 0.31, feedIn: 0.09),
      isLive: true,
      flowHistory: HomeEnergyFlowHistory(
        interval: interval,
        readings: HomeEnergyFlowHistory.Series.allCases.map {
          .init(series: $0, timestamp: interval.start, kilowatts: 1)
        }
      ),
      batteryHistory: HomeEnergyBatteryHistory(
        interval: interval,
        readings: [.init(timestamp: interval.start, stateOfCharge: 76)]
      ),
      priceHistory: history(endingAt: now),
      now: { now }
    )
  }

  private func waitForInitialRequests(_ loader: ControlledHomeEnergyHistoryLoader) async {
    await fulfillment(
      of: [loader.updateStreamStarted, loader.historyStarted(at: 0)],
      timeout: 1
    )
  }

  private func historyCompletion(
    for store: HomeAssistantHomeEnergyStore
  ) -> (expectation: XCTestExpectation, subscription: AnyCancellable) {
    let expectation = expectation(description: "Price history load completed")
    let subscription = store.priceHistoryStore.$isLoading
      .dropFirst()
      .filter { !$0 }
      .prefix(1)
      .sink { _ in expectation.fulfill() }
    return (expectation, subscription)
  }

  private func liveCompletion(
    for store: HomeAssistantHomeEnergyStore
  ) -> (expectation: XCTestExpectation, subscription: AnyCancellable) {
    let expectation = expectation(description: "Home energy became live")
    let subscription = store.$isLive
      .dropFirst()
      .filter { $0 }
      .prefix(1)
      .sink { _ in expectation.fulfill() }
    return (expectation, subscription)
  }

  private func stop(
    _ synchronization: Task<Void, Never>,
    loader: ControlledHomeEnergyHistoryLoader
  ) async {
    synchronization.cancel()
    loader.finishUpdates()
    await synchronization.value
  }

  private func history(endingAt end: Date) -> HomeEnergyPriceHistory {
    let start = end.addingTimeInterval(-60)
    return HomeEnergyPriceHistory(
      interval: DateInterval(start: start, end: end),
      readings: [
        .init(tariff: .general, timestamp: start, dollarsPerKilowattHour: 0.22),
        .init(tariff: .feedIn, timestamp: start, dollarsPerKilowattHour: 0.07),
      ]
    )
  }

  private func snapshot(
    general: Double,
    feedIn: Double
  ) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.4,
      batteryStateOfCharge: 76,
      homeConsumptionKilowatts: 3.1,
      gridPowerKilowatts: -2.7,
      generalPriceDollarsPerKilowattHour: general,
      feedInPriceDollarsPerKilowattHour: feedIn
    )
  }

  private func credentials() -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: nil,
      externalURL: nil,
      lastSuccessfulURL: URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

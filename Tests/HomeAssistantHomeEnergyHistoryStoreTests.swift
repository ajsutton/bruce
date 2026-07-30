import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantHomeEnergyHistoryStoreTests: XCTestCase {
  func testPendingHistoryLoadMergesEveryLivePriceTransition() async {
    let start = Date(timeIntervalSince1970: 100_000)
    let remoteEnd = start.addingTimeInterval(24 * 60 * 60)
    let dates = ControlledHomeEnergyDateSequence([
      remoteEnd.addingTimeInterval(10),
      remoteEnd.addingTimeInterval(20),
    ])
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = makeStore(loader: loader, dates: dates)
    let synchronization = Task {
      await store.synchronize(with: .connected(credentials()))
    }
    await waitForInitialRequests(loader)

    loader.yield(.live(snapshot(general: 0.41, feedIn: 0.08)))
    await fulfillment(of: [dates.requested(at: 0)], timeout: 1)
    loader.yield(.live(snapshot(general: 0.31, feedIn: 0.09)))
    await fulfillment(of: [dates.requested(at: 1)], timeout: 1)
    let completion = historyCompletion(for: store)
    loader.succeedHistory(
      0,
      with: history(start: start, end: remoteEnd, general: 0.22, feedIn: 0.07)
    )
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertEqual(
      prices(in: store.priceHistoryStore.priceHistory, for: .general),
      [0.22, 0.41, 0.31]
    )
    XCTAssertEqual(
      prices(in: store.priceHistoryStore.priceHistory, for: .feedIn),
      [0.07, 0.08, 0.09]
    )
    withExtendedLifetime(completion.subscription) {}
    await stop(synchronization, loader: loader)
  }

  func testHistoryFailureKeepsLiveSnapshotButDoesNotPromotePendingPrices() async {
    let date = Date(timeIntervalSince1970: 200_000)
    let dates = ControlledHomeEnergyDateSequence([date])
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = makeStore(loader: loader, dates: dates)
    let synchronization = Task {
      await store.synchronize(with: .connected(credentials()))
    }
    await waitForInitialRequests(loader)

    let liveSnapshot = snapshot(general: 0.41, feedIn: 0.08)
    loader.yield(.live(liveSnapshot))
    await fulfillment(of: [dates.requested(at: 0)], timeout: 1)
    let completion = historyCompletion(for: store)
    loader.failHistory(0, with: HistoryStoreTestError.failed)
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertEqual(store.snapshot, liveSnapshot)
    XCTAssertTrue(store.isLive)
    XCTAssertNil(store.problem)
    XCTAssertEqual(store.priceHistoryStore.priceHistory, .empty)
    XCTAssertFalse(store.priceHistoryStore.hasUsableHistory)
    XCTAssertTrue(store.priceHistoryStore.isUnavailable)
    withExtendedLifetime(completion.subscription) {}
    await stop(synchronization, loader: loader)
  }

  func testDisconnectedStoreRejectsPendingHistoryCompletion() async {
    let start = Date(timeIntervalSince1970: 300_000)
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = HomeAssistantHomeEnergyStore(loader: loader)
    let synchronization = Task {
      await store.synchronize(with: .connected(credentials()))
    }
    await waitForInitialRequests(loader)

    let cancelledHistoryLoad = store.reset()
    loader.succeedHistory(
      0,
      with: history(
        start: start,
        end: start.addingTimeInterval(24 * 60 * 60),
        general: 0.22,
        feedIn: 0.07
      )
    )
    await cancelledHistoryLoad?.value

    XCTAssertEqual(store.priceHistoryStore.priceHistory, .empty)
    XCTAssertFalse(store.priceHistoryStore.isLoading)
    await stop(synchronization, loader: loader)
  }

  func testLiveRecoveryReloadsHistoryToBackfillReconnectGap() async {
    let start = Date(timeIntervalSince1970: 400_000)
    let initialEnd = start.addingTimeInterval(24 * 60 * 60)
    let recoveredEnd = initialEnd.addingTimeInterval(60)
    let reconnectTrigger = initialEnd.addingTimeInterval(45)
    let dates = ControlledHomeEnergyDateSequence([reconnectTrigger])
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 2)
    let store = makeStore(loader: loader, dates: dates)
    let synchronization = Task {
      await store.synchronize(with: .connected(credentials()))
    }
    await waitForInitialRequests(loader)
    await completeHistory(
      0,
      on: store,
      loader: loader,
      history: history(start: start, end: initialEnd, general: 0.22, feedIn: 0.07)
    )

    loader.yield(.reconnecting(store.snapshot))
    loader.yield(.live(snapshot(general: 0.31, feedIn: 0.09)))
    await fulfillment(
      of: [dates.requested(at: 0), loader.historyStarted(at: 1)],
      timeout: 1
    )
    let recovered = HomeEnergyPriceHistory(
      interval: DateInterval(start: start, end: recoveredEnd),
      readings: [
        reading(.general, at: start, value: 0.22),
        reading(.feedIn, at: start, value: 0.07),
        reading(.general, at: initialEnd.addingTimeInterval(30), value: 0.51),
        reading(.feedIn, at: initialEnd.addingTimeInterval(30), value: 0.11),
      ]
    )
    await completeHistory(1, on: store, loader: loader, history: recovered)

    XCTAssertEqual(
      prices(in: store.priceHistoryStore.priceHistory, for: .general),
      [0.22, 0.51, 0.31]
    )
    XCTAssertEqual(
      prices(in: store.priceHistoryStore.priceHistory, for: .feedIn),
      [0.07, 0.11, 0.09]
    )
    XCTAssertFalse(store.priceHistoryStore.isStale)
    await stop(synchronization, loader: loader)
  }

  private func makeStore(
    loader: ControlledHomeEnergyHistoryLoader,
    dates: ControlledHomeEnergyDateSequence
  ) -> HomeAssistantHomeEnergyStore {
    HomeAssistantHomeEnergyStore(loader: loader, now: dates.next)
  }

  private func waitForInitialRequests(
    _ loader: ControlledHomeEnergyHistoryLoader
  ) async {
    await fulfillment(
      of: [loader.updateStreamStarted, loader.historyStarted(at: 0)],
      timeout: 1
    )
  }

  private func completeHistory(
    _ request: Int,
    on store: HomeAssistantHomeEnergyStore,
    loader: ControlledHomeEnergyHistoryLoader,
    history: HomeEnergyPriceHistory
  ) async {
    let completion = historyCompletion(for: store)
    loader.succeedHistory(request, with: history)
    await fulfillment(of: [completion.expectation], timeout: 1)
    withExtendedLifetime(completion.subscription) {}
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

  private func stop(
    _ synchronization: Task<Void, Never>,
    loader: ControlledHomeEnergyHistoryLoader
  ) async {
    synchronization.cancel()
    loader.finishUpdates()
    await synchronization.value
  }

  private func history(
    start: Date,
    end: Date,
    general: Double,
    feedIn: Double
  ) -> HomeEnergyPriceHistory {
    HomeEnergyPriceHistory(
      interval: DateInterval(start: start, end: end),
      readings: [
        reading(.general, at: start, value: general),
        reading(.feedIn, at: start, value: feedIn),
      ]
    )
  }

  private func reading(
    _ tariff: HomeEnergyPriceHistory.Tariff,
    at timestamp: Date,
    value: Double
  ) -> HomeEnergyPriceHistory.Reading {
    HomeEnergyPriceHistory.Reading(
      tariff: tariff,
      timestamp: timestamp,
      dollarsPerKilowattHour: value
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

  private func prices(
    in history: HomeEnergyPriceHistory,
    for tariff: HomeEnergyPriceHistory.Tariff
  ) -> [Double] {
    history.readings
      .filter { $0.tariff == tariff }
      .map(\.dollarsPerKilowattHour)
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

private enum HistoryStoreTestError: Error {
  case failed
}

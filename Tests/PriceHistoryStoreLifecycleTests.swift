import Combine
import XCTest

@testable import Bruce

@MainActor
final class PriceHistoryStoreLifecycleTests: XCTestCase {
  func testRefreshRetriesHistoryAfterAnInitialFailure() async {
    let start = Date(timeIntervalSince1970: 500_000)
    let end = start.addingTimeInterval(24 * 60 * 60)
    let dates = ControlledHomeEnergyDateSequence([end.addingTimeInterval(10)])
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 2)
    let store = HomeAssistantHomeEnergyStore(loader: loader, now: dates.next)
    let synchronization = Task {
      await store.synchronize(with: .ready(credentials()))
    }
    await fulfillment(
      of: [loader.updateStreamStarted, loader.historyStarted(at: 0)],
      timeout: 1
    )
    await failHistory(0, on: store, loader: loader)

    let liveSnapshot = snapshot(general: 0.31, feedIn: 0.09)
    loader.yield(.refreshing(liveSnapshot))
    loader.yield(.live(liveSnapshot))
    await fulfillment(
      of: [dates.requested(at: 0), loader.historyStarted(at: 1)],
      timeout: 1
    )
    await completeHistory(
      1,
      on: store,
      loader: loader,
      history: history(start: start, end: end)
    )

    XCTAssertTrue(store.priceHistoryStore.hasUsableHistory)
    XCTAssertFalse(store.priceHistoryStore.isStale)
    await stop(synchronization, loader: loader)
  }

  func testStreamTerminationMarksLoadedHistoryStale() async {
    let start = Date(timeIntervalSince1970: 600_000)
    let end = start.addingTimeInterval(24 * 60 * 60)
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = HomeAssistantHomeEnergyStore(loader: loader)
    let synchronization = Task {
      await store.synchronize(with: .ready(credentials()))
    }
    await fulfillment(
      of: [loader.updateStreamStarted, loader.historyStarted(at: 0)],
      timeout: 1
    )
    await completeHistory(
      0,
      on: store,
      loader: loader,
      history: history(start: start, end: end)
    )

    loader.finishUpdates()
    await synchronization.value

    XCTAssertTrue(store.priceHistoryStore.isStale)
    XCTAssertEqual(store.problem, .connectionUnavailable)
  }

  func testPartialRemoteHistoryCannotBeCompletedByPendingLivePrices() async {
    let start = Date(timeIntervalSince1970: 650_000)
    let end = start.addingTimeInterval(24 * 60 * 60)
    let dates = ControlledHomeEnergyDateSequence([end.addingTimeInterval(10)])
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = HomeAssistantHomeEnergyStore(loader: loader, now: dates.next)
    let synchronization = Task {
      await store.synchronize(with: .ready(credentials()))
    }
    await fulfillment(
      of: [loader.updateStreamStarted, loader.historyStarted(at: 0)],
      timeout: 1
    )
    loader.yield(.live(snapshot(general: 0.41, feedIn: 0.08)))
    await fulfillment(of: [dates.requested(at: 0)], timeout: 1)
    let partialHistory = HomeEnergyPriceHistory(
      interval: DateInterval(start: start, end: end),
      readings: [reading(.general, at: start, value: 0.22)]
    )

    await completeHistory(0, on: store, loader: loader, history: partialHistory)

    XCTAssertEqual(store.priceHistoryStore.priceHistory, .empty)
    XCTAssertFalse(store.priceHistoryStore.hasUsableHistory)
    XCTAssertTrue(store.priceHistoryStore.isUnavailable)
    XCTAssertNil(store.priceHistoryStore.problem)
    await stop(synchronization, loader: loader)
  }

  func testHistoryAuthenticationFailureRequestsSignIn() async {
    var requiresAuthentication = false
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = HomeAssistantHomeEnergyStore(
      loader: loader,
      onAuthenticationRequired: {
        requiresAuthentication = true
      }
    )
    let synchronization = Task {
      await store.synchronize(with: .ready(credentials()))
    }
    await fulfillment(
      of: [loader.updateStreamStarted, loader.historyStarted(at: 0)],
      timeout: 1
    )

    let completion = historyCompletion(for: store)
    loader.failHistory(0, with: HomeAssistantAPIError.unauthorized)
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertEqual(store.problem, .signInRequired)
    XCTAssertTrue(requiresAuthentication)
    XCTAssertTrue(store.priceHistoryStore.isUnavailable)
    XCTAssertNil(store.priceHistoryStore.problem)
    withExtendedLifetime(completion.subscription) {}
    await stop(synchronization, loader: loader)
  }

  func testResetBeforeTaskStartsDoesNotBeginAHistoryRequest() async {
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = HomeEnergyPriceHistoryStore(loader: loader)

    store.reload()
    let cancelledLoad = store.reset()
    await cancelledLoad?.value

    XCTAssertEqual(loader.historyRequestCount, 0)
    XCTAssertFalse(store.isLoading)
    XCTAssertTrue(store.isUnavailable)
  }

  func testPendingHistoryRequestDoesNotRetainItsStore() async {
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    var store: HomeEnergyPriceHistoryStore? = HomeEnergyPriceHistoryStore(loader: loader)
    weak let weakStore = store
    store?.reload()
    await fulfillment(of: [loader.historyStarted(at: 0)], timeout: 1)

    store = nil

    XCTAssertNil(weakStore)
    loader.failHistory(0, with: CancellationError())
  }

  func testCancellingSynchronizationInvalidatesPendingHistoryRequest() async {
    let start = Date(timeIntervalSince1970: 700_000)
    let end = start.addingTimeInterval(24 * 60 * 60)
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = HomeAssistantHomeEnergyStore(loader: loader)
    let synchronization = Task {
      await store.synchronize(with: .ready(credentials()))
    }
    await fulfillment(
      of: [loader.updateStreamStarted, loader.historyStarted(at: 0)],
      timeout: 1
    )

    synchronization.cancel()
    loader.finishUpdates()
    await synchronization.value

    XCTAssertFalse(store.priceHistoryStore.isLoading)
    XCTAssertTrue(store.priceHistoryStore.isUnavailable)

    loader.succeedHistory(0, with: history(start: start, end: end))
    await fulfillment(of: [loader.historyFinished(at: 0)], timeout: 1)

    XCTAssertEqual(store.priceHistoryStore.priceHistory, .empty)
    XCTAssertFalse(store.priceHistoryStore.hasUsableHistory)
  }

  private func failHistory(
    _ request: Int,
    on store: HomeAssistantHomeEnergyStore,
    loader: ControlledHomeEnergyHistoryLoader
  ) async {
    let completion = historyCompletion(for: store)
    loader.failHistory(request, with: HistoryLifecycleTestError.failed)
    await fulfillment(of: [completion.expectation], timeout: 1)
    XCTAssertEqual(store.priceHistoryStore.problem, .loadFailed)
    withExtendedLifetime(completion.subscription) {}
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

  private func history(start: Date, end: Date) -> HomeEnergyPriceHistory {
    HomeEnergyPriceHistory(
      interval: DateInterval(start: start, end: end),
      readings: [
        reading(.general, at: start, value: 0.22),
        reading(.feedIn, at: start, value: 0.07),
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

private enum HistoryLifecycleTestError: Error {
  case failed
}

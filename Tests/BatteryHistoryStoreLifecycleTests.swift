import Combine
import XCTest

@testable import Bruce

@MainActor
final class BatteryHistoryStoreLifecycleTests: XCTestCase {
  func testResetRejectsLateHistoryCompletion() async {
    let loader = ControlledBatteryHistoryLoader(batteryRequestCount: 1)
    let store = HomeEnergyBatteryHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.batteryStarted(at: 0)], timeout: 1)

    let cancelledLoad = store.reset()
    loader.succeedBattery(0, with: batteryHistory(charge: 34))
    await fulfillment(of: [loader.batteryFinished(at: 0)], timeout: 1)
    await cancelledLoad?.value

    XCTAssertEqual(store.batteryHistory, .empty)
    XCTAssertFalse(store.hasUsableHistory)
    XCTAssertFalse(store.isLoading)
    XCTAssertTrue(store.isUnavailable)
  }

  func testReplacementRejectsLateResultFromOlderLoad() async {
    let loader = ControlledBatteryHistoryLoader(batteryRequestCount: 2)
    let store = HomeEnergyBatteryHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.batteryStarted(at: 0)], timeout: 1)
    store.reload()
    await fulfillment(of: [loader.batteryStarted(at: 1)], timeout: 1)
    let completion = loadCompletion(for: store)

    loader.succeedBattery(1, with: batteryHistory(charge: 63))
    await fulfillment(of: [completion.expectation], timeout: 1)
    loader.succeedBattery(0, with: batteryHistory(charge: 12))
    await fulfillment(of: [loader.batteryFinished(at: 0)], timeout: 1)

    XCTAssertEqual(
      store.batteryHistory.readings.compactMap(\.stateOfCharge),
      [63]
    )
    withExtendedLifetime(completion.subscription) {}
  }

  func testPendingRequestDoesNotRetainBatteryStore() async {
    let loader = ControlledBatteryHistoryLoader(batteryRequestCount: 1)
    var store: HomeEnergyBatteryHistoryStore? = HomeEnergyBatteryHistoryStore(loader: loader)
    weak let weakStore = store
    store?.reload()
    await fulfillment(of: [loader.batteryStarted(at: 0)], timeout: 1)

    store = nil

    XCTAssertNil(weakStore)
    loader.failBattery(0, with: CancellationError())
  }

  func testSuccessfulEmptyHistoryHasNoLoadProblem() async {
    let loader = ControlledBatteryHistoryLoader(batteryRequestCount: 1)
    let store = HomeEnergyBatteryHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.batteryStarted(at: 0)], timeout: 1)
    let completion = loadCompletion(for: store)

    loader.succeedBattery(0, with: .empty)
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertTrue(store.isUnavailable)
    XCTAssertNil(store.problem)
    withExtendedLifetime(completion.subscription) {}
  }

  func testInitialHistoryFailureHasLoadProblem() async {
    let loader = ControlledBatteryHistoryLoader(batteryRequestCount: 1)
    let store = HomeEnergyBatteryHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.batteryStarted(at: 0)], timeout: 1)
    let completion = loadCompletion(for: store)

    loader.failBattery(0, with: BatteryHistoryLifecycleError.failed)
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertTrue(store.isUnavailable)
    XCTAssertEqual(store.problem, .loadFailed)
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

  private func batteryHistory(charge: Double) -> HomeEnergyBatteryHistory {
    let start = Date(timeIntervalSince1970: 100_000)
    return batteryHistory(
      start: start,
      end: start.addingTimeInterval(24 * 60 * 60),
      charge: charge
    )
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

}

private enum BatteryHistoryLifecycleError: Error {
  case failed
}

import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeEnergyBatteryHistoryStoreTests: XCTestCase {
  func testPendingHistoryLoadMergesNewestLiveChargeAtGraphResolution() async {
    let start = Date(timeIntervalSince1970: 100_000)
    let remoteEnd = start.addingTimeInterval(24 * 60 * 60)
    let loader = ControlledBatteryHistoryLoader(batteryRequestCount: 1)
    let store = HomeEnergyBatteryHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.batteryStarted(at: 0)], timeout: 1)

    store.record(
      snapshot: snapshot(charge: 41),
      at: remoteEnd.addingTimeInterval(10)
    )
    store.record(
      snapshot: snapshot(charge: 43),
      at: remoteEnd.addingTimeInterval(20)
    )
    let completion = loadCompletion(for: store)
    loader.succeedBattery(
      0,
      with: HomeEnergyBatteryHistory(
        interval: DateInterval(start: start, end: remoteEnd),
        readings: [
          HomeEnergyBatteryHistory.Reading(
            timestamp: start,
            stateOfCharge: 34
          )
        ]
      )
    )
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertEqual(
      store.batteryHistory.readings.map(\.stateOfCharge),
      [34, 43]
    )
    XCTAssertEqual(
      store.batteryHistory.readings.last?.timestamp,
      remoteEnd.addingTimeInterval(20)
    )
    XCTAssertTrue(store.hasUsableHistory)
    XCTAssertFalse(store.isStale)
    withExtendedLifetime(completion.subscription) {}
  }

  func testFailedReloadKeepsLoadedHistoryAsLastKnown() async {
    let timestamp = Date(timeIntervalSince1970: 100_000)
    let history = HomeEnergyBatteryHistory(
      interval: DateInterval(start: timestamp, duration: 24 * 60 * 60),
      readings: [
        HomeEnergyBatteryHistory.Reading(
          timestamp: timestamp,
          stateOfCharge: 34
        )
      ]
    )
    let loader = ControlledBatteryHistoryLoader(batteryRequestCount: 1)
    let store = HomeEnergyBatteryHistoryStore(
      loader: loader,
      batteryHistory: history
    )
    store.reload()
    await fulfillment(of: [loader.batteryStarted(at: 0)], timeout: 1)
    let completion = loadCompletion(for: store)

    loader.failBattery(0, with: BatteryHistoryStoreTestError.failed)
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertEqual(store.batteryHistory, history)
    XCTAssertTrue(store.hasUsableHistory)
    XCTAssertTrue(store.isStale)
    XCTAssertFalse(store.isUnavailable)
    XCTAssertEqual(store.problem, .loadFailed)
    withExtendedLifetime(completion.subscription) {}
  }

  func testUnavailablePendingChargeEndsTheRemoteHistoryLine() async {
    let start = Date(timeIntervalSince1970: 100_000)
    let remoteEnd = start.addingTimeInterval(24 * 60 * 60)
    let unavailableAt = remoteEnd.addingTimeInterval(20)
    let mergedStart = unavailableAt.addingTimeInterval(-24 * 60 * 60)
    let loader = ControlledBatteryHistoryLoader(batteryRequestCount: 1)
    let store = HomeEnergyBatteryHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.batteryStarted(at: 0)], timeout: 1)

    store.record(
      snapshot: snapshot(charge: nil),
      at: unavailableAt
    )
    let completion = loadCompletion(for: store)
    loader.succeedBattery(
      0,
      with: HomeEnergyBatteryHistory(
        interval: DateInterval(start: start, end: remoteEnd),
        readings: [.init(timestamp: start, stateOfCharge: 34)]
      )
    )
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertEqual(
      store.batteryHistory.readings,
      [
        .init(timestamp: mergedStart, stateOfCharge: 34),
        .init(timestamp: unavailableAt, stateOfCharge: nil),
      ]
    )
    XCTAssertEqual(
      store.batteryHistory.availableReadingSegments.first?.last?.timestamp,
      unavailableAt
    )
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

  private func snapshot(charge: Double?) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: nil,
      batteryStateOfCharge: charge,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil
    )
  }
}

private enum BatteryHistoryStoreTestError: Error {
  case failed
}

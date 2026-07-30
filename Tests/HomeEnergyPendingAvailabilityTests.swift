import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeEnergyPendingAvailabilityTests: XCTestCase {
  func testPendingBatteryLoadPreservesRapidAvailabilityTransitions() async {
    let start = Date(timeIntervalSince1970: 800_000)
    let remoteEnd = start.addingTimeInterval(24 * 60 * 60)
    let loader = ControlledBatteryHistoryLoader(batteryRequestCount: 1)
    let store = HomeEnergyBatteryHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.batteryStarted(at: 0)], timeout: 1)

    for (offset, charge) in [(1.0, 41.0), (2, nil), (3, 43)] {
      store.record(
        snapshot: batterySnapshot(charge: charge),
        at: remoteEnd.addingTimeInterval(offset)
      )
    }
    let completion = batteryLoadCompletion(for: store)
    loader.succeedBattery(
      0,
      with: HomeEnergyBatteryHistory(
        interval: DateInterval(start: start, end: remoteEnd),
        readings: [.init(timestamp: start, stateOfCharge: 34)]
      )
    )
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertEqual(
      store.batteryHistory.readings.filter { $0.timestamp > remoteEnd },
      [
        .init(
          timestamp: remoteEnd.addingTimeInterval(1),
          stateOfCharge: 41
        ),
        .init(
          timestamp: remoteEnd.addingTimeInterval(2),
          stateOfCharge: nil
        ),
        .init(
          timestamp: remoteEnd.addingTimeInterval(3),
          stateOfCharge: 43
        ),
      ]
    )
    withExtendedLifetime(completion.subscription) {}
  }

  func testPendingPriceLoadPreservesRapidAvailabilityTransitions() async {
    let start = Date(timeIntervalSince1970: 900_000)
    let remoteEnd = start.addingTimeInterval(24 * 60 * 60)
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = HomeEnergyPriceHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.historyStarted(at: 0)], timeout: 1)

    for (offset, general) in [(1.0, 0.31), (2, nil), (3, 0.33)] {
      store.record(
        snapshot: priceSnapshot(general: general),
        at: remoteEnd.addingTimeInterval(offset)
      )
    }
    let completion = priceLoadCompletion(for: store)
    loader.succeedHistory(
      0,
      with: HomeEnergyPriceHistory(
        interval: DateInterval(start: start, end: remoteEnd),
        readings: [
          priceReading(.general, at: start, value: 0.22),
          priceReading(.feedIn, at: start, value: 0.07),
        ]
      )
    )
    await fulfillment(of: [completion.expectation], timeout: 1)

    XCTAssertEqual(
      store.priceHistory.readings.filter {
        $0.tariff == .general && $0.timestamp > remoteEnd
      },
      [
        priceReading(
          .general,
          at: remoteEnd.addingTimeInterval(1),
          value: 0.31
        ),
        priceReading(
          .general,
          at: remoteEnd.addingTimeInterval(2),
          value: nil
        ),
        priceReading(
          .general,
          at: remoteEnd.addingTimeInterval(3),
          value: 0.33
        ),
      ]
    )
    withExtendedLifetime(completion.subscription) {}
  }

  private func batteryLoadCompletion(
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

  private func priceLoadCompletion(
    for store: HomeEnergyPriceHistoryStore
  ) -> (expectation: XCTestExpectation, subscription: AnyCancellable) {
    let expectation = expectation(description: "Price history load completed")
    let subscription = store.$isLoading
      .dropFirst()
      .filter { !$0 }
      .prefix(1)
      .sink { _ in expectation.fulfill() }
    return (expectation, subscription)
  }

  private func batterySnapshot(
    charge: Double?
  ) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: nil,
      batteryStateOfCharge: charge,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil
    )
  }

  private func priceSnapshot(
    general: Double?
  ) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: nil,
      batteryStateOfCharge: nil,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: general,
      feedInPriceDollarsPerKilowattHour: 0.07
    )
  }

  private func priceReading(
    _ tariff: HomeEnergyPriceHistory.Tariff,
    at timestamp: Date,
    value: Double?
  ) -> HomeEnergyPriceHistory.Reading {
    HomeEnergyPriceHistory.Reading(
      tariff: tariff,
      timestamp: timestamp,
      dollarsPerKilowattHour: value
    )
  }
}

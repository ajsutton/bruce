import Combine
import XCTest

@testable import Bruce

@MainActor
final class PriceHistorySamplingTests: XCTestCase {
  func testLivePriceHistoryCoalescesUpdatesToGraphResolution() {
    let (end, initialHistory) = historyFixture()
    let store = HomeEnergyPriceHistoryStore(
      loader: ControlledHomeEnergyHistoryLoader(historyRequestCount: 0),
      priceHistory: initialHistory
    )

    store.record(
      snapshot: snapshot(general: 0.31, feedIn: 0.09),
      at: end.addingTimeInterval(1)
    )
    store.record(
      snapshot: snapshot(general: 0.32, feedIn: 0.08),
      at: end.addingTimeInterval(2)
    )
    XCTAssertEqual(store.priceHistory, initialHistory)

    let sampleTimestamp = end.addingTimeInterval(
      HomeEnergyHistorySampling.interval
    )
    store.record(
      snapshot: snapshot(general: 0.33, feedIn: 0.07),
      at: sampleTimestamp
    )

    XCTAssertEqual(store.priceHistory.interval.end, sampleTimestamp)
    assertLatestPrices(store.priceHistory, general: 0.33, feedIn: 0.07)
  }

  func testPendingLivePriceBurstMergesOnlyNewestSample() async {
    let (end, initialHistory) = historyFixture()
    let loader = ControlledHomeEnergyHistoryLoader(historyRequestCount: 1)
    let store = HomeEnergyPriceHistoryStore(loader: loader)
    store.reload()
    await fulfillment(of: [loader.historyStarted(at: 0)], timeout: 1)

    for (offset, general, feedIn) in [
      (1.0, 0.31, 0.09),
      (2.0, 0.32, 0.08),
      (3.0, 0.33, 0.06),
    ] {
      store.record(
        snapshot: snapshot(general: general, feedIn: feedIn),
        at: end.addingTimeInterval(offset)
      )
    }
    let completed = expectation(description: "Price history load completed")
    let subscription = store.$isLoading
      .dropFirst()
      .filter { !$0 }
      .prefix(1)
      .sink { _ in completed.fulfill() }
    loader.succeedHistory(0, with: initialHistory)
    await fulfillment(of: [completed], timeout: 1)

    XCTAssertEqual(
      store.priceHistory.readings.filter { $0.timestamp > end },
      [
        reading(.feedIn, at: end.addingTimeInterval(3), value: 0.06),
        reading(.general, at: end.addingTimeInterval(3), value: 0.33),
      ]
    )
    withExtendedLifetime(subscription) {}
  }

  func testSingleLivePriceUpdateFlushesAfterSampleBoundary() async {
    let (end, initialHistory) = historyFixture()
    let delay = ControlledHomeEnergyDelay(delayCount: 1)
    let store = HomeEnergyPriceHistoryStore(
      loader: ControlledHomeEnergyHistoryLoader(historyRequestCount: 0),
      priceHistory: initialHistory,
      sampleSleep: { try? await delay.sleep($0) }
    )
    let flushed = expectation(description: "Trailing price sample flushed")
    let subscription = store.$priceHistory
      .dropFirst()
      .filter { $0 != initialHistory }
      .prefix(1)
      .sink { _ in flushed.fulfill() }

    store.record(
      snapshot: snapshot(general: 0.31, feedIn: 0.09),
      at: end.addingTimeInterval(0.001)
    )
    XCTAssertEqual(store.priceHistory, initialHistory)

    await fulfillment(of: [delay.started(at: 0)], timeout: 1)
    delay.finish(0)
    await fulfillment(of: [flushed], timeout: 1)
    XCTAssertEqual(store.priceHistory.interval.end, end.addingTimeInterval(0.001))
    assertLatestPrices(store.priceHistory, general: 0.31, feedIn: 0.09)
    withExtendedLifetime(subscription) {}
  }

  func testPriceAvailabilityTransitionPublishesImmediately() {
    let (end, initialHistory) = historyFixture()
    let store = HomeEnergyPriceHistoryStore(
      loader: ControlledHomeEnergyHistoryLoader(historyRequestCount: 0),
      priceHistory: initialHistory
    )
    let timestamp = end.addingTimeInterval(1)

    store.record(
      snapshot: snapshot(general: nil, feedIn: 0.07),
      at: timestamp
    )

    XCTAssertEqual(store.priceHistory.interval.end, timestamp)
    XCTAssertNil(
      store.priceHistory.readings.last(where: { $0.tariff == .general })?
        .dollarsPerKilowattHour
    )
  }

  private func historyFixture() -> (
    end: Date,
    history: HomeEnergyPriceHistory
  ) {
    let start = Date(timeIntervalSince1970: 400_000)
    let end = start.addingTimeInterval(24 * 60 * 60)
    return (
      end,
      HomeEnergyPriceHistory(
        interval: DateInterval(start: start, end: end),
        readings: [
          reading(.general, at: start, value: 0.22),
          reading(.feedIn, at: start, value: 0.07),
        ]
      )
    )
  }

  private func assertLatestPrices(
    _ history: HomeEnergyPriceHistory,
    general: Double,
    feedIn: Double
  ) {
    XCTAssertEqual(
      history.readings.last(where: { $0.tariff == .general })?
        .dollarsPerKilowattHour,
      general
    )
    XCTAssertEqual(
      history.readings.last(where: { $0.tariff == .feedIn })?
        .dollarsPerKilowattHour,
      feedIn
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
    general: Double?,
    feedIn: Double?
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
}

import XCTest

@testable import Bruce

final class HomeEnergyPriceHistoryTests: XCTestCase {
  func testRecordingPreservesActivePricesAtTheRollingWindowStart() {
    let start = Date(timeIntervalSince1970: 100_000)
    let initialSnapshot = snapshot(general: 0.22, feedIn: 0.07)

    let initial = HomeEnergyPriceHistory.empty.recording(
      snapshot: initialSnapshot,
      at: start
    )
    let unchanged = initial.recording(
      snapshot: initialSnapshot,
      at: start.addingTimeInterval(60 * 60)
    )
    let nextDay = unchanged.recording(
      snapshot: snapshot(general: 0.41, feedIn: 0.07),
      at: start.addingTimeInterval(25 * 60 * 60)
    )

    XCTAssertEqual(initial.readings.count, 2)
    XCTAssertEqual(unchanged.readings, initial.readings)
    XCTAssertEqual(nextDay.readings.count, 3)
    XCTAssertEqual(
      nextDay.interval.duration,
      24 * 60 * 60,
      accuracy: 0.001
    )
    XCTAssertEqual(
      nextDay.readings.map(\.dollarsPerKilowattHour),
      [0.07, 0.22, 0.41]
    )
    XCTAssertEqual(
      Set(nextDay.readings.prefix(2).map(\.timestamp)),
      [nextDay.interval.start]
    )
  }

  func testRenderingExtendsUnchangedPricesToTheIntervalEnd() {
    let start = Date(timeIntervalSince1970: 100_000)
    let end = start.addingTimeInterval(24 * 60 * 60)
    let history = HomeEnergyPriceHistory(
      interval: DateInterval(start: start, end: end),
      readings: [
        reading(.general, at: start, value: 0.22),
        reading(.feedIn, at: start, value: 0.07),
      ]
    )

    let rendered = history.readingsExtendingToIntervalEnd

    XCTAssertEqual(rendered.count, 4)
    XCTAssertEqual(
      Set(rendered.suffix(2).map(\.timestamp)),
      [end]
    )
    XCTAssertEqual(
      rendered.suffix(2).map(\.dollarsPerKilowattHour),
      [0.07, 0.22]
    )
  }

  func testRollingWindowKeepsAnActualChangeAtTheExactStartBoundary() {
    let originalStart = Date(timeIntervalSince1970: 100_000)
    let nextStart = originalStart.addingTimeInterval(60 * 60)
    let end = nextStart.addingTimeInterval(24 * 60 * 60)
    let history = HomeEnergyPriceHistory(
      interval: DateInterval(start: originalStart, end: nextStart),
      readings: [
        reading(.general, at: originalStart, value: 0.22),
        reading(.feedIn, at: originalStart, value: 0.07),
        reading(.general, at: nextStart, value: 0.41),
      ]
    )

    let rolled = history.recording(
      snapshot: snapshot(general: 0.41, feedIn: 0.07),
      at: end
    )

    XCTAssertEqual(
      rolled.readings.first(where: { $0.tariff == .general })?
        .dollarsPerKilowattHour,
      0.41
    )
  }

  func testMergingHistoryPreservesEveryLivePriceTransition() {
    let start = Date(timeIntervalSince1970: 100_000)
    let remoteEnd = start.addingTimeInterval(23 * 60 * 60)
    let firstLiveUpdate = remoteEnd.addingTimeInterval(10)
    let secondLiveUpdate = remoteEnd.addingTimeInterval(20)
    let remote = HomeEnergyPriceHistory(
      interval: DateInterval(start: start, end: remoteEnd),
      readings: [
        reading(.general, at: start, value: 0.22),
        reading(.feedIn, at: start, value: 0.07),
      ]
    )
    let live = HomeEnergyPriceHistory(
      interval: DateInterval(start: start, end: secondLiveUpdate),
      readings: [
        reading(.general, at: firstLiveUpdate, value: 0.41),
        reading(.general, at: secondLiveUpdate, value: 0.31),
      ]
    )

    let merged = remote.mergingLiveReadings(from: live)

    XCTAssertEqual(
      merged.readings.filter { $0.tariff == .general }
        .map(\.dollarsPerKilowattHour),
      [0.22, 0.41, 0.31]
    )
    XCTAssertEqual(merged.interval.end, secondLiveUpdate)
  }

  private func snapshot(
    general: Double,
    feedIn: Double
  ) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: nil,
      batteryStateOfCharge: nil,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: general,
      feedInPriceDollarsPerKilowattHour: feedIn
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
}

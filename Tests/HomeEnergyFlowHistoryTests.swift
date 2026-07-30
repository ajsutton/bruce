import XCTest

@testable import Bruce

final class HomeEnergyFlowHistoryTests: XCTestCase {
  func testRecordingPreservesActiveFlowsAtTheRollingWindowStart() {
    let start = Date(timeIntervalSince1970: 100_000)
    let initialSnapshot = snapshot(solar: 8, home: 2, grid: -2, battery: -4)

    let initial = HomeEnergyFlowHistory.empty.recording(
      snapshot: initialSnapshot,
      at: start
    )
    let unchanged = initial.recording(
      snapshot: initialSnapshot,
      at: start.addingTimeInterval(60 * 60)
    )
    let nextDay = unchanged.recording(
      snapshot: snapshot(solar: 0, home: 3, grid: 1, battery: 2),
      at: start.addingTimeInterval(25 * 60 * 60)
    )

    XCTAssertEqual(initial.readings.count, 4)
    XCTAssertEqual(unchanged.readings, initial.readings)
    XCTAssertEqual(nextDay.readings.count, 8)
    XCTAssertEqual(Set(nextDay.readings.prefix(4).map(\.timestamp)), [nextDay.interval.start])
    XCTAssertEqual(nextDay.interval.duration, 24 * 60 * 60, accuracy: 0.001)
  }

  func testRenderingBreaksOnlyTheUnavailableSeries() {
    let start = Date(timeIntervalSince1970: 100_000)
    let unavailable = start.addingTimeInterval(60)
    let availableAgain = unavailable.addingTimeInterval(60)
    let end = availableAgain.addingTimeInterval(60)
    let history = HomeEnergyFlowHistory(
      interval: DateInterval(start: start, end: end),
      readings: [
        reading(.pvGeneration, at: start, kilowatts: 8),
        reading(.homeUsage, at: start, kilowatts: 2),
        reading(.grid, at: start, kilowatts: -2),
        reading(.battery, at: start, kilowatts: -4),
        reading(.grid, at: unavailable, kilowatts: nil),
        reading(.grid, at: availableAgain, kilowatts: 1),
      ]
    )

    let segments = history.availableReadingSegments

    XCTAssertEqual(segments[.grid]?.count, 2)
    XCTAssertEqual(segments[.grid]?[0].map(\.timestamp), [start, unavailable])
    XCTAssertEqual(segments[.grid]?[1].map(\.timestamp), [availableAgain, end])
    XCTAssertEqual(segments[.pvGeneration]?.count, 1)
    XCTAssertEqual(segments[.homeUsage]?.count, 1)
    XCTAssertEqual(segments[.battery]?.count, 1)
  }

  func testMergingPreservesEveryLiveFlowTransition() {
    let start = Date(timeIntervalSince1970: 100_000)
    let remoteEnd = start.addingTimeInterval(23 * 60 * 60)
    let liveTimestamp = remoteEnd.addingTimeInterval(30)
    let remote = history(
      from: snapshot(solar: 8, home: 2, grid: -2, battery: -4),
      at: start,
      end: remoteEnd
    )
    let live = HomeEnergyFlowHistory.empty.recording(
      snapshot: snapshot(solar: 0, home: 4, grid: 1, battery: 3),
      at: liveTimestamp
    )

    let merged = remote.mergingLiveReadings(from: live)

    XCTAssertEqual(merged.interval.end, liveTimestamp)
    XCTAssertEqual(
      merged.readings.last(where: { $0.series == .battery })?.kilowatts,
      3
    )
    XCTAssertEqual(
      merged.readings.last(where: { $0.series == .grid })?.kilowatts,
      1
    )
  }

  private func history(
    from snapshot: HomeAssistantHomeEnergySnapshot,
    at start: Date,
    end: Date
  ) -> HomeEnergyFlowHistory {
    let recorded = HomeEnergyFlowHistory.empty.recording(
      snapshot: snapshot,
      at: start
    )
    return HomeEnergyFlowHistory(
      interval: DateInterval(start: start, end: end),
      readings: recorded.readings
    )
  }

  private func snapshot(
    solar: Double?,
    home: Double?,
    grid: Double?,
    battery: Double?
  ) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: solar,
      batteryStateOfCharge: nil,
      batteryPowerKilowatts: battery,
      homeConsumptionKilowatts: home,
      gridPowerKilowatts: grid,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil
    )
  }

  private func reading(
    _ series: HomeEnergyFlowHistory.Series,
    at timestamp: Date,
    kilowatts: Double?
  ) -> HomeEnergyFlowHistory.Reading {
    HomeEnergyFlowHistory.Reading(
      series: series,
      timestamp: timestamp,
      kilowatts: kilowatts
    )
  }
}

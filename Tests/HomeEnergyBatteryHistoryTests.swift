import XCTest

@testable import Bruce

final class HomeEnergyBatteryHistoryTests: XCTestCase {
  func testRecordingPreservesActiveChargeAtTheRollingWindowStart() {
    let start = Date(timeIntervalSince1970: 100_000)
    let initial = HomeEnergyBatteryHistory.empty.recording(
      snapshot: snapshot(charge: 34),
      at: start
    )
    let unchanged = initial.recording(
      snapshot: snapshot(charge: 34),
      at: start.addingTimeInterval(60 * 60)
    )
    let nextDay = unchanged.recording(
      snapshot: snapshot(charge: 41),
      at: start.addingTimeInterval(25 * 60 * 60)
    )

    XCTAssertEqual(initial.readings.count, 1)
    XCTAssertEqual(unchanged.readings, initial.readings)
    XCTAssertEqual(nextDay.readings.map(\.stateOfCharge), [34, 41])
    XCTAssertEqual(nextDay.readings.first?.timestamp, nextDay.interval.start)
    XCTAssertEqual(nextDay.interval.duration, 24 * 60 * 60, accuracy: 0.001)
  }

  func testRenderingExtendsUnchangedChargeToTheIntervalEnd() {
    let start = Date(timeIntervalSince1970: 100_000)
    let end = start.addingTimeInterval(24 * 60 * 60)
    let history = HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, end: end),
      readings: [reading(at: start, charge: 34)]
    )

    let rendered = history.readingsExtendingToIntervalEnd

    XCTAssertEqual(rendered.map(\.timestamp), [start, end])
    XCTAssertEqual(rendered.map(\.stateOfCharge), [34, 34])
  }

  func testMergingHistoryPreservesEveryLiveChargeTransition() {
    let start = Date(timeIntervalSince1970: 100_000)
    let remoteEnd = start.addingTimeInterval(23 * 60 * 60)
    let firstLiveUpdate = remoteEnd.addingTimeInterval(10)
    let secondLiveUpdate = remoteEnd.addingTimeInterval(20)
    let remote = HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, end: remoteEnd),
      readings: [reading(at: start, charge: 34)]
    )
    let live = HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, end: secondLiveUpdate),
      readings: [
        reading(at: firstLiveUpdate, charge: 41),
        reading(at: secondLiveUpdate, charge: 43),
      ]
    )

    let merged = remote.mergingLiveReadings(from: live)

    XCTAssertEqual(merged.readings.map(\.stateOfCharge), [34, 41, 43])
    XCTAssertEqual(merged.interval.end, secondLiveUpdate)
  }

  func testMergingUsesLatestObservationWhenChargeDoesNotChange() {
    let start = Date(timeIntervalSince1970: 100_000)
    let remoteEnd = start.addingTimeInterval(23 * 60 * 60)
    let firstLiveUpdate = remoteEnd.addingTimeInterval(10)
    let latestObservation = remoteEnd.addingTimeInterval(20)
    let remote = HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, end: remoteEnd),
      readings: [reading(at: start, charge: 34)]
    )
    let live = HomeEnergyBatteryHistory.empty
      .recording(snapshot: snapshot(charge: 41), at: firstLiveUpdate)
      .recording(snapshot: snapshot(charge: 41), at: latestObservation)

    let merged = remote.mergingLiveReadings(from: live)

    XCTAssertEqual(merged.readings.map(\.stateOfCharge), [34, 41])
    XCTAssertEqual(merged.interval.end, latestObservation)
  }

  func testRecordingPreservesAnInitialUnavailableCharge() {
    let timestamp = Date(timeIntervalSince1970: 100_000)

    let history = HomeEnergyBatteryHistory.empty.recording(
      snapshot: snapshot(charge: nil),
      at: timestamp
    )

    XCTAssertEqual(
      history.readings,
      [.init(timestamp: timestamp, stateOfCharge: nil)]
    )
  }

  func testRenderingBreaksTheLineWhileChargeIsUnavailable() {
    let start = Date(timeIntervalSince1970: 100_000)
    let unavailable = start.addingTimeInterval(60)
    let availableAgain = unavailable.addingTimeInterval(60)
    let end = availableAgain.addingTimeInterval(60)
    let history = HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, end: end),
      readings: [
        reading(at: start, charge: 34),
        .init(timestamp: unavailable, stateOfCharge: nil),
        reading(at: availableAgain, charge: 41),
      ]
    )

    let segments = history.availableReadingSegments

    XCTAssertEqual(segments.count, 2)
    XCTAssertEqual(segments[0].map(\.timestamp), [start, unavailable])
    XCTAssertEqual(segments[0].compactMap(\.stateOfCharge), [34, 34])
    XCTAssertEqual(segments[1].map(\.timestamp), [availableAgain, end])
    XCTAssertEqual(segments[1].compactMap(\.stateOfCharge), [41, 41])
  }

  func testRecordingMarksTheStartAndEndOfAnAvailabilityGap() {
    let start = Date(timeIntervalSince1970: 100_000)
    let unavailable = start.addingTimeInterval(60)
    let availableAgain = unavailable.addingTimeInterval(60)

    let history = HomeEnergyBatteryHistory.empty
      .recording(snapshot: snapshot(charge: 34), at: start)
      .recording(snapshot: snapshot(charge: nil), at: unavailable)
      .recording(snapshot: snapshot(charge: 41), at: availableAgain)

    XCTAssertEqual(
      history.readings,
      [
        reading(at: start, charge: 34),
        .init(timestamp: unavailable, stateOfCharge: nil),
        reading(at: availableAgain, charge: 41),
      ]
    )
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

  private func reading(
    at timestamp: Date,
    charge: Double
  ) -> HomeEnergyBatteryHistory.Reading {
    HomeEnergyBatteryHistory.Reading(
      timestamp: timestamp,
      stateOfCharge: charge
    )
  }
}

import XCTest

@testable import Bruce

final class ClimateHistoryTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_790_200_000)
  private var zone: ClimateHistoryZone { ClimateHistoryZone.all[0] }

  func testSystemOffOverridesEnabledZoneAndOpenDamper() throws {
    let value = try value(system: "off", room: "fan_only", opening: 85)
    XCTAssertEqual(value.activity, .off)
    XCTAssertEqual(value.opening, 0)
    XCTAssertEqual(value.actual, 24)
    XCTAssertEqual(value.target, 21)
  }

  func testDisabledZoneHasZeroOpeningWhileSystemIsOn() throws {
    let value = try value(system: "cool", room: "off", opening: 85)
    XCTAssertEqual(value.activity, .off)
    XCTAssertEqual(value.opening, 0)
  }

  func testEnabledZoneShowsReportedOpeningWhenSystemIsOn() throws {
    let value = try value(system: "cool", room: "fan_only", opening: 85)
    XCTAssertEqual(value.activity, .active)
    XCTAssertEqual(value.opening, 85)
  }

  func testUnknownSystemLeavesActivityAndOpeningUnknown() throws {
    let value = try value(system: "unavailable", room: "fan_only", opening: 85)
    XCTAssertEqual(value.activity, .unknown)
    XCTAssertNil(value.opening)
    XCTAssertEqual(value.actual, 24)
  }

  func testKnownOffZoneStillShowsOffWhenSystemIsUnknown() throws {
    XCTAssertEqual(try value(system: "unknown", room: "off", opening: 85).activity, .off)
  }

  func testAttributeChangesUseUpdateTimeRatherThanModeChangeTime() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      [
        entry(zone.id, state: "fan_only", seconds: 0, attributes: ["current_temperature": 24]),
        entry(zone.id, state: "fan_only", seconds: 300, attributes: ["current_temperature": 23]),
      ]
    ])
    let history = try ClimateHistory(
      data: data, interval: DateInterval(start: start, duration: 600))
    XCTAssertEqual(history.frames.map(\.timestamp), [start, start.addingTimeInterval(300)])
    XCTAssertEqual(history.points(for: zone).map(\.value.actual), [24, 23, 23])
  }

  func testTargetIsPreservedWhenActualTemperatureIsMissing() throws {
    let states = try decode([
      entry(zone.id, state: "off", seconds: 0, attributes: ["temperature": 21])
    ])
    let value = ClimateHistory.Frame(timestamp: start, states: states).values[zone.id]
    XCTAssertNil(value?.actual)
    XCTAssertEqual(value?.target, 21)
  }

  func testMissingDataSplitsTemperatureTraceInsteadOfBridgingGap() {
    let points = [24.0, nil, 23.0].enumerated().map { index, value in
      ClimateHistoryPoint(
        timestamp: start.addingTimeInterval(Double(index) * 60),
        value: ClimateHistoryValue(actual: value, target: nil, opening: nil, activity: .unknown))
    }
    let traces = ClimateHistoryChartData(points: points).traces
    XCTAssertEqual(traces.count, 2)
    XCTAssertEqual(traces[0].points.map(\.value), [24, 24])
    XCTAssertEqual(traces[0].points.last?.timestamp, start.addingTimeInterval(60))
    XCTAssertEqual(traces[1].points.first?.timestamp, start.addingTimeInterval(120))
  }

  func testSystemTransitionChangesAllZoneActivityAtItsTimestamp() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      [
        entry(ClimateHistoryZone.systemID, state: "cool", seconds: 0),
        entry(ClimateHistoryZone.systemID, state: "off", seconds: 300),
      ],
      [entry(zone.id, state: "fan_only", seconds: 0, attributes: ["current_temperature": 24])],
    ])
    let history = try ClimateHistory(
      data: data, interval: DateInterval(start: start, duration: 600))
    XCTAssertEqual(history.points(for: zone).map(\.value.activity), [.active, .off, .off])
    XCTAssertEqual(history.frames.last?.values["climate.ella"]?.activity, .off)
  }

  func testMalformedTimestampIsRejected() throws {
    let data = Data(
      #"[[{"entity_id":"climate.lounge","state":"off","attributes":{},"last_updated":"bad"}]]"#.utf8
    )
    XCTAssertThrowsError(
      try ClimateHistory(data: data, interval: DateInterval(start: start, duration: 600)))
  }

  func testHistoryTrimsOldFramesButRetainsBoundaryValue() {
    var history = ClimateHistory(
      interval: DateInterval(start: start, duration: 60),
      frames: [
        .init(
          timestamp: start,
          values: [zone.id: .init(actual: 24, target: nil, opening: nil, activity: .off)])
      ])
    history.append(.init(timestamp: start.addingTimeInterval(120), values: [:]), duration: 60)
    XCTAssertEqual(history.points(for: zone).first?.timestamp, start.addingTimeInterval(60))
    XCTAssertEqual(history.points(for: zone).first?.value.actual, 24)
  }

  private func value(system: String, room: String, opening: Double) throws -> ClimateHistoryValue {
    let states = try decode([
      entry(ClimateHistoryZone.systemID, state: system, seconds: 0),
      entry(
        zone.id, state: room, seconds: 0,
        attributes: ["current_temperature": 24, "temperature": 21]),
      entry(zone.damperID, state: "open", seconds: 0, attributes: ["current_position": opening]),
    ])
    return try XCTUnwrap(ClimateHistory.Frame(timestamp: start, states: states).values[zone.id])
  }

  private func decode(_ entries: [[String: Any]]) throws -> [HomeAssistantState] {
    try JSONDecoder().decode(
      [HomeAssistantState].self, from: JSONSerialization.data(withJSONObject: entries))
  }

  private func entry(_ id: String, state: String, seconds: Double, attributes: [String: Any] = [:])
    -> [String: Any]
  {
    [
      "entity_id": id, "state": state, "attributes": attributes,
      "last_changed": start.ISO8601Format(),
      "last_updated": start.addingTimeInterval(seconds).ISO8601Format(),
    ]
  }
}

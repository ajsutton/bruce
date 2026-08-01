import XCTest

@testable import Bruce

final class HomeAssistantTemperatureSummaryTests: XCTestCase {
  func testPresetsAreOrderedAllLabelsFloorsNoneAndSelectionMatchesExactZoneState() {
    let downstairs = HomeAssistantClimateFloor(
      id: "downstairs",
      name: "Downstairs",
      level: 0
    )
    let upstairs = HomeAssistantClimateFloor(id: "upstairs", name: "Upstairs", level: 1)
    let summary = HomeAssistantTemperatureSummary(
      readings: [
        groupedZone(
          id: "climate.living",
          floor: downstairs,
          presetLabels: [.init(id: "shared", name: "Shared")],
          powerState: .poweredOn
        ),
        groupedZone(
          id: "climate.bedroom",
          floor: upstairs,
          presetLabels: [.init(id: "bedrooms", name: "Bedrooms")],
          powerState: .off
        ),
      ]
    )

    XCTAssertEqual(
      summary.climatePresets.map(\.id),
      [
        .all,
        .label("bedrooms"),
        .label("shared"),
        .floor("downstairs"),
        .floor("upstairs"),
        .none,
      ]
    )
    XCTAssertEqual(summary.selectedClimatePresetID, .label("shared"))
  }

  func testAverageUsesAvailableRoomsRatherThanAirConditionerTemperature() {
    let summary = HomeAssistantTemperatureSummary(
      readings: [
        reading(id: "climate.ac_0", value: 30, kind: .airConditioner),
        reading(id: "climate.dining", value: 20, kind: .zone),
        reading(id: "climate.bedroom", value: 24, kind: .zone, powerState: .off),
        reading(
          id: "climate.study",
          value: 50,
          kind: .zone,
          powerState: .unavailable
        ),
      ]
    )

    XCTAssertEqual(summary.averageRoomTemperature, 22)
  }

  func testAverageIsUnavailableWithoutAvailableRooms() {
    let summary = HomeAssistantTemperatureSummary(
      readings: [
        reading(id: "climate.ac_0", value: 30, kind: .airConditioner),
        reading(
          id: "climate.study",
          value: 50,
          kind: .zone,
          powerState: .unavailable
        ),
      ]
    )

    XCTAssertNil(summary.averageRoomTemperature)
  }

  func testTargetsUseTheMostPreciseAdvertisedStep() {
    let summary = HomeAssistantTemperatureSummary(
      readings: [
        reading(
          id: "climate.ac_0",
          value: 24,
          targetValue: 18,
          targetValueStep: 1,
          kind: .airConditioner
        ),
        reading(
          id: "climate.living",
          value: 22,
          targetValue: 18,
          targetValueStep: 0.5,
          kind: .zone
        ),
      ]
    )

    XCTAssertEqual(summary.targetValueFractionLength, 1)
  }

  private func reading(
    id: String,
    value: Double,
    targetValue: Double? = nil,
    targetValueStep: Double? = nil,
    kind: HomeAssistantTemperatureReading.Kind,
    powerState: HomeAssistantTemperatureReading.PowerState = .poweredOn
  ) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: id,
      name: id,
      value: value,
      targetValue: targetValue,
      unit: "°C",
      powerState: powerState,
      kind: kind,
      targetValueStep: targetValueStep
    )
  }

  private func groupedZone(
    id: String,
    floor: HomeAssistantClimateFloor,
    presetLabels: [HomeAssistantClimatePresetLabel],
    powerState: HomeAssistantTemperatureReading.PowerState
  ) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: id,
      name: id,
      value: 22,
      targetValue: nil,
      unit: "°C",
      powerState: powerState,
      kind: .zone,
      operatingMode: powerState == .off ? .off : .cooling,
      floor: floor,
      presetLabels: presetLabels
    )
  }
}

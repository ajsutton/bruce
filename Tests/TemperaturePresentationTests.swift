import XCTest

@testable import Bruce

@MainActor
final class TemperaturePresentationTests: XCTestCase {
  func testValuesAtDisplayedPrecisionHaveTheSamePresentation() {
    let current = [
      reading(id: "first", value: 22.41),
      reading(id: "second", value: 23.41),
    ]
    let samePresentation = [
      reading(id: "first", value: 22.44),
      reading(id: "second", value: 23.44),
    ]
    let changedPresentation = [
      reading(id: "first", value: 22.46),
      reading(id: "second", value: 23.44),
    ]

    XCTAssertTrue(
      HomeAssistantTemperaturePresentation.matches(
        current,
        samePresentation
      )
    )
    XCTAssertFalse(
      HomeAssistantTemperaturePresentation.matches(
        current,
        changedPresentation
      )
    )
  }

  func testUndisplayedAirConditionerTemperatureDoesNotChangePresentation() {
    let current = [
      reading(id: "air-conditioner", value: 21, kind: .airConditioner),
      reading(id: "room", value: 22.4),
    ]
    let candidate = [
      reading(id: "air-conditioner", value: 28, kind: .airConditioner),
      reading(id: "room", value: 22.4),
    ]

    XCTAssertTrue(
      HomeAssistantTemperaturePresentation.matches(current, candidate)
    )
  }

  func testRoomCardEqualityTracksDisplayedTemperature() {
    let current = HomeAssistantTemperatureCard(
      reading: reading(id: "room", value: 22.41),
      mode: .standard
    )
    let samePresentation = HomeAssistantTemperatureCard(
      reading: reading(id: "room", value: 22.44),
      mode: .standard
    )
    let changedPresentation = HomeAssistantTemperatureCard(
      reading: reading(id: "room", value: 22.46),
      mode: .standard
    )

    XCTAssertEqual(current, samePresentation)
    XCTAssertNotEqual(current, changedPresentation)
  }

  func testAirConditionerCardEqualityIgnoresUndisplayedTemperature() {
    let current = HomeAssistantAirConditionerCard(
      reading: reading(
        id: "air-conditioner",
        value: 21,
        kind: .airConditioner
      ),
      averageValue: 22.4,
      mode: .standard
    )
    let candidate = HomeAssistantAirConditionerCard(
      reading: reading(
        id: "air-conditioner",
        value: 28,
        kind: .airConditioner
      ),
      averageValue: 22.4,
      mode: .standard
    )

    XCTAssertEqual(current, candidate)
  }

  private func reading(
    id: String,
    value: Double,
    kind: HomeAssistantTemperatureReading.Kind = .other
  ) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: id,
      name: id.localizedCapitalized,
      value: value,
      targetValue: 23,
      unit: "°C",
      powerState: .poweredOn,
      kind: kind
    )
  }
}

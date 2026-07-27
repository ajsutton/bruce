import XCTest

@testable import Bruce

final class HomeAssistantTemperatureIconTests: XCTestCase {
  func testRoomIconsMapToNativeSymbols() {
    XCTAssertEqual(
      HomeAssistantTemperatureIcon.systemImageName(for: "mdi:sofa"),
      "sofa.fill"
    )
    XCTAssertEqual(
      HomeAssistantTemperatureIcon.systemImageName(for: "mdi:bed"),
      "bed.double.fill"
    )
    XCTAssertEqual(
      HomeAssistantTemperatureIcon.systemImageName(for: "mdi:desk"),
      "desktopcomputer"
    )
    XCTAssertEqual(
      HomeAssistantTemperatureIcon.systemImageName(for: "mdi:table-chair"),
      "table.furniture.fill"
    )
  }

  func testClimateIconsMapToNativeSymbols() {
    XCTAssertEqual(
      HomeAssistantTemperatureIcon.systemImageName(for: "mdi:fan"),
      "fan.fill"
    )
    XCTAssertEqual(
      HomeAssistantTemperatureIcon.systemImageName(for: "mdi:snowflake"),
      "snowflake"
    )
    XCTAssertEqual(
      HomeAssistantTemperatureIcon.systemImageName(for: "mdi:radiator"),
      "flame.fill"
    )
  }

  func testMissingOrUnknownIconUsesThermometer() {
    XCTAssertEqual(
      HomeAssistantTemperatureIcon.systemImageName(for: nil),
      "thermometer.medium"
    )
    XCTAssertEqual(
      HomeAssistantTemperatureIcon.systemImageName(for: "mdi:robot"),
      "thermometer.medium"
    )
  }
}

import XCTest

@testable import Bruce

final class HomeAssistantTemperatureIconTests: XCTestCase {
  override func setUp() {
    super.setUp()
    HomeAssistantMaterialDesignIcon.prepare()
  }

  func testBundledMaterialDesignIconsResolveByHomeAssistantIdentifier() throws {
    let expectedCodepoints: [String: UInt32] = [
      "mdi:sofa": 0xF04B9,
      "mdi:bed": 0xF02E3,
      "mdi:human-child": 0xF02E7,
      "mdi:office-building": 0xF0991,
      "mdi:table-furniture": 0xF05BC,
    ]

    for (identifier, expectedCodepoint) in expectedCodepoints {
      let glyph = try XCTUnwrap(HomeAssistantMaterialDesignIcon.glyph(for: identifier))
      XCTAssertEqual(glyph.unicodeScalars.first?.value, expectedCodepoint)
    }
  }

  func testMissingOrUnknownIconHasNoMaterialDesignGlyph() {
    XCTAssertNil(HomeAssistantMaterialDesignIcon.glyph(for: nil))
    XCTAssertNil(HomeAssistantMaterialDesignIcon.glyph(for: "mdi:not-a-real-icon"))
    XCTAssertNil(HomeAssistantMaterialDesignIcon.glyph(for: "sf:sofa"))
  }
}

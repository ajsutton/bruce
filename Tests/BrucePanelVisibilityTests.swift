import XCTest

@testable import Bruce

final class BrucePanelVisibilityTests: XCTestCase {
  func testFullyVisibleShortPanelWinsOverPartlyVisibleLongPanel() {
    let frames: [BrucePanel: CGRect] = [
      .car: CGRect(x: 0, y: 0, width: 700, height: 220),
      .energy: CGRect(x: 0, y: 220, width: 700, height: 600),
    ]

    let panel = BrucePanelVisibility.mostVisiblePanel(
      in: frames,
      viewportHeight: 800
    )

    XCTAssertEqual(panel, .car)
  }

  func testLongPanelWinsAfterShortPanelScrollsPartlyOffscreen() {
    let frames: [BrucePanel: CGRect] = [
      .car: CGRect(x: 0, y: -100, width: 700, height: 220),
      .energy: CGRect(x: 0, y: 120, width: 700, height: 600),
    ]

    let panel = BrucePanelVisibility.mostVisiblePanel(
      in: frames,
      viewportHeight: 800
    )

    XCTAssertEqual(panel, .energy)
  }
}

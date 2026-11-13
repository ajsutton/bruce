import XCTest

@testable import Bruce

final class BrucePanelSwipeNavigationTests: XCTestCase {
  func testHorizontalSwipesMoveToTheAdjacentPanel() {
    XCTAssertEqual(destination(from: .climate, direction: .left), .car)
    XCTAssertEqual(destination(from: .car, direction: .left), .energy)
    XCTAssertEqual(destination(from: .energy, direction: .right), .car)
    XCTAssertEqual(destination(from: .car, direction: .right), .climate)
    #if os(iOS)
      XCTAssertEqual(destination(from: .energy, direction: .left), .voice)
      XCTAssertEqual(destination(from: .voice, direction: .right), .energy)
    #endif
  }

  func testSwipesAtTheFirstAndLastPanelDoNothing() {
    XCTAssertNil(destination(from: .climate, direction: .right))
    #if os(iOS)
      XCTAssertNil(destination(from: .voice, direction: .left))
    #else
      XCTAssertNil(destination(from: .energy, direction: .left))
    #endif
  }

  private func destination(
    from panel: BrucePanel,
    direction: BrucePanelSwipeDirection
  ) -> BrucePanel? {
    BrucePanelSwipeNavigation.destination(from: panel, direction: direction)
  }
}

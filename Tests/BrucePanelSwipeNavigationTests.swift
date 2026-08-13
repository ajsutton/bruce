import XCTest

@testable import Bruce

final class BrucePanelSwipeNavigationTests: XCTestCase {
  func testHorizontalSwipesMoveToTheAdjacentPanel() {
    XCTAssertEqual(destination(from: .climate, direction: .left), .car)
    XCTAssertEqual(destination(from: .car, direction: .left), .energy)
    XCTAssertEqual(destination(from: .energy, direction: .right), .car)
    XCTAssertEqual(destination(from: .car, direction: .right), .climate)
  }

  func testSwipesAtTheFirstAndLastPanelDoNothing() {
    XCTAssertNil(destination(from: .climate, direction: .right))
    XCTAssertNil(destination(from: .energy, direction: .left))
  }

  private func destination(
    from panel: BrucePanel,
    direction: BrucePanelSwipeDirection
  ) -> BrucePanel? {
    BrucePanelSwipeNavigation.destination(from: panel, direction: direction)
  }
}

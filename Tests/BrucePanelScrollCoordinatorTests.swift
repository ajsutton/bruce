import XCTest

@testable import Bruce

final class BrucePanelScrollCoordinatorTests: XCTestCase {
  func testForwardRouteVisitsEachAdjacentPanel() {
    var coordinator = BrucePanelScrollCoordinator()
    let request = coordinator.activate(from: .climate, to: .energy)

    let firstCommand = coordinator.begin(request, animated: true)
    XCTAssertEqual(firstCommand?.panel, .car)
    XCTAssertEqual(firstCommand?.animated, true)

    let secondCommand = coordinator.complete(.car)
    XCTAssertEqual(secondCommand?.panel, .energy)
    XCTAssertNil(coordinator.complete(.energy))
    XCTAssertNil(coordinator.activePanel)
  }

  func testReverseRouteVisitsEachAdjacentPanel() {
    var coordinator = BrucePanelScrollCoordinator()
    let request = coordinator.activate(from: .energy, to: .climate)

    XCTAssertEqual(coordinator.begin(request, animated: false)?.panel, .car)
    XCTAssertEqual(coordinator.complete(.car)?.panel, .climate)
    XCTAssertNil(coordinator.complete(.climate))
    XCTAssertNil(coordinator.activePanel)
  }

  func testSamePanelAtTopNeedsNoScrollButCanRetryAwayFromTop() {
    var coordinator = BrucePanelScrollCoordinator()
    coordinator.request(from: .climate, to: .climate, panelIsAtTop: true)

    XCTAssertNil(coordinator.activePanel)
    XCTAssertNil(coordinator.pendingRequest)

    coordinator.request(from: .climate, to: .climate, panelIsAtTop: false)
    guard let request = coordinator.pendingRequest else {
      XCTFail("Expected a retry request.")
      return
    }

    XCTAssertEqual(coordinator.begin(request, animated: true)?.panel, .climate)
    XCTAssertNil(coordinator.complete(.climate))
    XCTAssertNil(coordinator.activePanel)
  }

  func testReplacementRejectsOldRequestAndStaleCompletion() {
    var coordinator = BrucePanelScrollCoordinator()
    let replacedRequest = coordinator.activate(from: .climate, to: .energy)
    XCTAssertEqual(coordinator.begin(replacedRequest, animated: true)?.panel, .car)

    coordinator.request(from: .energy, to: .climate, panelIsAtTop: false)
    guard let replacementRequest = coordinator.pendingRequest else {
      XCTFail("Expected a replacement request.")
      return
    }

    XCTAssertNil(coordinator.begin(replacedRequest, animated: true))
    XCTAssertEqual(coordinator.begin(replacementRequest, animated: true)?.panel, .car)
    XCTAssertNil(coordinator.complete(.energy))
    XCTAssertEqual(coordinator.activePanel, .climate)
    XCTAssertEqual(coordinator.complete(.car)?.panel, .climate)
  }

  func testCancellationRejectsPendingCommandsAndCompletions() {
    var coordinator = BrucePanelScrollCoordinator()
    let request = coordinator.activate(from: .climate, to: .energy)
    XCTAssertEqual(coordinator.begin(request, animated: true)?.panel, .car)

    coordinator.cancel()

    XCTAssertNil(coordinator.activePanel)
    XCTAssertNil(coordinator.begin(request, animated: true))
    XCTAssertNil(coordinator.complete(.car))
  }
}

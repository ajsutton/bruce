import XCTest

@testable import Bruce

@MainActor
final class BruceModeTransitionTests: XCTestCase {
  func testSelectedModeIsVisibleWhileIconChangeAwaitsConfirmation() async {
    let store = TestModeStore(localMode: .standard)
    let didSuspend = expectation(description: "Full Bruce icon application suspended")
    let iconApplier = SuspendingIconApplier(suspendingMode: .full, didSuspend: didSuspend)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.restore()

    controller.requestSelection(.full)
    await fulfillment(of: [didSuspend], timeout: 1)

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(store.localMode, .standard)

    iconApplier.resume()
    await controller.waitForTransitions()
  }
}

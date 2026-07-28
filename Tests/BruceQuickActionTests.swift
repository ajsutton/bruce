#if os(iOS)
  import UIKit
  import XCTest

  @testable import Bruce

  @MainActor
  final class BruceQuickActionTests: XCTestCase {
    func testManageConnectionQuickActionRequestsConnectionManagement() {
      let delegate = BruceSceneDelegate()
      let shortcutItem = UIApplicationShortcutItem(
        type: BruceQuickAction.manageConnectionType,
        localizedTitle: "Manage Connection"
      )

      let handled = delegate.handle(shortcutItem)

      XCTAssertTrue(handled)
      XCTAssertEqual(delegate.manageConnectionRequestID, 1)
    }

    func testUnknownQuickActionIsNotHandled() {
      let delegate = BruceSceneDelegate()
      let shortcutItem = UIApplicationShortcutItem(
        type: "net.symphonious.bruce.unknown",
        localizedTitle: "Unknown"
      )

      let handled = delegate.handle(shortcutItem)

      XCTAssertFalse(handled)
      XCTAssertEqual(delegate.manageConnectionRequestID, 0)
    }
  }
#endif

import XCTest

@testable import Bruce

#if os(iOS)
  import UIKit
#endif

final class HomeAssistantProjectConfigurationTests: XCTestCase {
  @MainActor
  func testIOSAppProvidesManageConnectionQuickAction() throws {
    let plist = try loadPropertyList("Info-iOS.plist")
    let shortcutItems = try XCTUnwrap(
      plist["UIApplicationShortcutItems"] as? [[String: Any]]
    )
    let shortcut = try XCTUnwrap(shortcutItems.first)
    let shortcutType = try XCTUnwrap(
      shortcut["UIApplicationShortcutItemType"] as? String
    )

    XCTAssertEqual(
      shortcutType,
      "net.symphonious.bruce.manageConnection"
    )
    XCTAssertEqual(
      shortcut["UIApplicationShortcutItemTitle"] as? String,
      "Manage Connection"
    )

    #if os(iOS)
      XCTAssertEqual(shortcutType, BruceQuickAction.manageConnectionType)
      let delegate = BruceSceneDelegate()
      let shortcutItem = UIApplicationShortcutItem(
        type: shortcutType,
        localizedTitle: "Manage Connection"
      )
      XCTAssertTrue(delegate.handle(shortcutItem))
    #endif
  }

  func testBothAppsDeclareBonjourAndLocalHTTPNetworking() throws {
    for filename in ["Info-iOS.plist", "Info-macOS.plist"] {
      let propertyList = try loadPropertyList(filename)
      XCTAssertEqual(
        propertyList["NSBonjourServices"] as? [String],
        ["_home-assistant._tcp"]
      )
      XCTAssertNotNil(propertyList["NSLocalNetworkUsageDescription"] as? String)
      let transportSecurity = try XCTUnwrap(
        propertyList["NSAppTransportSecurity"] as? [String: Any]
      )
      XCTAssertEqual(transportSecurity["NSAllowsLocalNetworking"] as? Bool, true)
      XCTAssertNil(transportSecurity["NSAllowsArbitraryLoads"])
      if filename == "Info-iOS.plist" {
        XCTAssertEqual(
          transportSecurity["NSAllowsArbitraryLoadsInWebContent"] as? Bool,
          true
        )
        let exceptionDomains = try XCTUnwrap(
          transportSecurity["NSExceptionDomains"] as? [String: Any]
        )
        XCTAssertEqual(Set(exceptionDomains.keys), ["lan"])
        let lanException = try XCTUnwrap(exceptionDomains["lan"] as? [String: Any])
        XCTAssertEqual(lanException["NSExceptionAllowsInsecureHTTPLoads"] as? Bool, true)
        XCTAssertEqual(lanException["NSIncludesSubdomains"] as? Bool, true)
      } else {
        XCTAssertNil(transportSecurity["NSAllowsArbitraryLoadsInWebContent"])
        XCTAssertNil(transportSecurity["NSExceptionDomains"])
      }
    }
  }

  func testReleaseAndDebugAssociatedDomainsMatchTheOAuthCallbackHost() throws {
    let releaseEntitlements = try loadPropertyList("Bruce.entitlements")
    XCTAssertEqual(
      releaseEntitlements["com.apple.developer.associated-domains"] as? [String],
      ["webcredentials:bruce.symphonious.net"]
    )
    let debugEntitlements = try loadPropertyList("Bruce-Debug.entitlements")
    XCTAssertEqual(
      debugEntitlements["com.apple.developer.associated-domains"] as? [String],
      ["webcredentials:bruce.symphonious.net"]
    )
  }

  func testDebugAndTestAppsHaveDistinctIdentities() throws {
    let project = try String(
      contentsOf: resourceURL("project.yml"),
      encoding: .utf8
    )

    XCTAssertTrue(project.contains("APP_DISPLAY_NAME: Bruce Debug"))
    XCTAssertEqual(
      project.components(separatedBy: "PRODUCT_BUNDLE_IDENTIFIER: net.symphonious.bruce.tests-host")
        .count - 1,
      2
    )
    for filename in ["Info-iOS.plist", "Info-macOS.plist"] {
      let propertyList = try loadPropertyList(filename)
      XCTAssertEqual(propertyList["CFBundleDisplayName"] as? String, "$(APP_DISPLAY_NAME)")
      XCTAssertEqual(propertyList["CFBundleName"] as? String, "$(APP_DISPLAY_NAME)")
    }
  }

  func testAssociationFileAuthorizesReleaseAndDebugAppIdentifiers() throws {
    let data = try Data(
      contentsOf: resourceURL("apple-app-site-association")
    )
    let association = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let webCredentials = try XCTUnwrap(association["webcredentials"] as? [String: Any])
    XCTAssertEqual(
      webCredentials["apps"] as? [String],
      [
        "P8LX6DFJM4.net.symphonious.bruce",
        "P8LX6DFJM4.net.symphonious.bruce.debug",
      ]
    )
  }

  private func loadPropertyList(_ filename: String) throws -> [String: Any] {
    let data = try Data(contentsOf: resourceURL(filename))
    return try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
  }

  private func resourceURL(_ filename: String) throws -> URL {
    try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: filename, withExtension: nil),
      "Missing test resource \(filename)."
    )
  }
}

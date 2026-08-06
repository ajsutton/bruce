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
      XCTAssertEqual(transportSecurity["NSAllowsArbitraryLoads"] as? Bool, true)
      XCTAssertNil(transportSecurity["NSAllowsLocalNetworking"])
      XCTAssertNil(transportSecurity["NSAllowsArbitraryLoadsForMedia"])
      XCTAssertNil(transportSecurity["NSAllowsArbitraryLoadsInWebContent"])
      XCTAssertNil(transportSecurity["NSExceptionDomains"])
    }
  }

  func testMacAppProvidesTheSharedWidgetKeychainGroup() throws {
    let propertyList = try loadPropertyList("Info-macOS.plist")

    XCTAssertEqual(
      propertyList["BruceSharedKeychainAccessGroup"] as? String,
      "$(SHARED_KEYCHAIN_ACCESS_GROUP)"
    )
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

  func testAppsAndWidgetsShareOnlyTheirMatchingContainersAndKeychains() throws {
    let releaseMacApp = try loadPropertyList("Bruce.entitlements")
    let debugMacApp = try loadPropertyList("Bruce-Debug.entitlements")
    let releaseApp = try loadPropertyList("Bruce-iOS.entitlements")
    let debugApp = try loadPropertyList("Bruce-iOS-Debug.entitlements")
    let releaseWidget = try loadPropertyList("EnergyWidget.entitlements")
    let debugWidget = try loadPropertyList("EnergyWidget-Debug.entitlements")
    let releaseMacWidget = try loadPropertyList("EnergyWidget-macOS.entitlements")
    let debugMacWidget = try loadPropertyList("EnergyWidget-macOS-Debug.entitlements")

    for entitlements in [releaseMacApp, releaseApp, releaseWidget, releaseMacWidget] {
      XCTAssertEqual(
        entitlements["com.apple.security.application-groups"] as? [String],
        ["group.net.symphonious.bruce"]
      )
      XCTAssertEqual(
        entitlements["keychain-access-groups"] as? [String],
        ["$(AppIdentifierPrefix)net.symphonious.bruce.shared"]
      )
    }
    for entitlements in [debugMacApp, debugApp, debugWidget, debugMacWidget] {
      XCTAssertEqual(
        entitlements["com.apple.security.application-groups"] as? [String],
        ["group.net.symphonious.bruce.debug"]
      )
      XCTAssertEqual(
        entitlements["keychain-access-groups"] as? [String],
        ["$(AppIdentifierPrefix)net.symphonious.bruce.debug.shared"]
      )
    }
    for entitlements in [releaseMacWidget, debugMacWidget] {
      XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
      XCTAssertEqual(entitlements["com.apple.security.network.client"] as? Bool, true)
    }
  }

  func testProjectEmbedsEnergyWidgetWithDistinctReleaseAndDebugIdentities() throws {
    let project = try String(
      contentsOf: resourceURL("project.yml"),
      encoding: .utf8
    )

    XCTAssertTrue(project.contains("BruceEnergyWidget:"))
    XCTAssertTrue(project.contains("BruceEnergyWidget_macOS:"))
    XCTAssertEqual(
      project.split(separator: "\n").count {
        $0.trimmingCharacters(in: .whitespaces) == "embed: true"
      },
      2
    )
    XCTAssertTrue(
      project.contains(
        "PRODUCT_BUNDLE_IDENTIFIER: net.symphonious.bruce.energy-widget"
      )
    )
    XCTAssertTrue(
      project.contains(
        "PRODUCT_BUNDLE_IDENTIFIER: net.symphonious.bruce.debug.energy-widget"
      )
    )
    XCTAssertTrue(
      project.contains(
        "PROVISIONING_PROFILE_SPECIFIER: ${MAC_WIDGET_PROVISIONING_PROFILE}"
      )
    )
  }

  func testDebugAndTestAppsHaveDistinctIdentities() throws {
    let project = try String(
      contentsOf: resourceURL("project.yml"),
      encoding: .utf8
    )

    XCTAssertTrue(project.contains("APP_DISPLAY_NAME: Bruce Debug"))
    XCTAssertEqual(
      project.split(separator: "\n").count {
        $0.trimmingCharacters(in: .whitespaces)
          == "PRODUCT_BUNDLE_IDENTIFIER: net.symphonious.bruce.tests-host"
      },
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

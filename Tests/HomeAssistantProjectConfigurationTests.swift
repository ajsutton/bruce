import XCTest

final class HomeAssistantProjectConfigurationTests: XCTestCase {
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

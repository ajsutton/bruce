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

  func testAssociatedDomainMatchesTheOAuthCallbackHost() throws {
    let entitlements = try loadPropertyList("Bruce.entitlements")

    XCTAssertEqual(
      entitlements["com.apple.developer.associated-domains"] as? [String],
      ["webcredentials:bruce.symphonious.net"]
    )
  }

  private func loadPropertyList(_ filename: String) throws -> [String: Any] {
    let appDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "App")
    let data = try Data(contentsOf: appDirectory.appending(path: filename))
    return try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
  }
}

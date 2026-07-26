import XCTest

@testable import Bruce

final class HomeAssistantRedirectPolicyTests: XCTestCase {
  func testAllowsSameOriginRedirect() throws {
    let original = try XCTUnwrap(URL(string: "https://home.example:443/auth/start"))
    let redirected = try XCTUnwrap(URL(string: "https://HOME.example/auth/finish"))

    XCTAssertTrue(HomeAssistantRedirectPolicy.allowsRedirect(from: original, to: redirected))
  }

  func testRejectsCrossOriginAndSchemeOrPortChanges() throws {
    let original = try XCTUnwrap(URL(string: "https://home.example/auth/start"))
    let crossOrigin = try XCTUnwrap(URL(string: "https://other.example/auth/finish"))
    let changedPort = try XCTUnwrap(URL(string: "https://home.example:8443/auth/finish"))
    let changedScheme = try XCTUnwrap(URL(string: "http://home.example/auth/finish"))

    XCTAssertFalse(HomeAssistantRedirectPolicy.allowsRedirect(from: original, to: crossOrigin))
    XCTAssertFalse(HomeAssistantRedirectPolicy.allowsRedirect(from: original, to: changedPort))
    XCTAssertFalse(HomeAssistantRedirectPolicy.allowsRedirect(from: original, to: changedScheme))
  }

  func testRejectsHTTPSDowngrade() throws {
    let original = try XCTUnwrap(URL(string: "https://home.example/auth/start"))
    let redirected = try XCTUnwrap(URL(string: "http://home.example:443/auth/finish"))

    XCTAssertFalse(HomeAssistantRedirectPolicy.allowsRedirect(from: original, to: redirected))
  }
}

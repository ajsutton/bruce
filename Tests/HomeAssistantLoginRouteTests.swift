import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantLoginRouteTests: XCTestCase {
  func testDiscoveredHomeUsesExternalHTTPSForBrowserAndTokenExchange() async throws {
    let fixture = CoordinatorFixture()
    let instance = HomeAssistantInstance(
      id: "home", name: "Home", version: nil,
      internalURL: fixture.internalURL, externalURL: fixture.externalURL, isOnboarding: false
    )
    let candidate = try XCTUnwrap(HomeAssistantServerSelection.candidate(from: instance))
    fixture.authenticationLoader.results = [.success(fixture.tokenResponse, statusCode: 200)]
    fixture.apiLoader.results = [.success(fixture.statusResponse, statusCode: 200)]

    _ = try await fixture.makeCoordinator().authenticate(to: candidate)

    let browserURL = try XCTUnwrap(fixture.browser.authenticationURLs.first)
    XCTAssertTrue(candidate.usesUnencryptedRoute)
    XCTAssertEqual(browserURL.scheme, "https")
    XCTAssertEqual(browserURL.host(), fixture.externalURL.host())
    let tokenURL = try XCTUnwrap(fixture.authenticationLoader.requests.first?.url)
    XCTAssertEqual(tokenURL, fixture.externalURL.appending(path: "auth/token"))
  }

  func testEncryptedDiscoveryRoutesDoNotRequireHTTPConsent() throws {
    let externalURL = try XCTUnwrap(URL(string: "https://home.example"))
    let internalURL = try XCTUnwrap(URL(string: "https://home.local:8123"))
    let instance = HomeAssistantInstance(
      id: "home", name: "Home", version: nil,
      internalURL: internalURL, externalURL: externalURL, isOnboarding: false
    )

    let candidate = try XCTUnwrap(HomeAssistantServerSelection.candidate(from: instance))

    XCTAssertEqual(candidate.activeURL, externalURL)
    XCTAssertFalse(candidate.usesUnencryptedRoute)
  }

  func testDiscoveryFallsBackToInternalURLWhenExternalURLIsMissingOrUnencrypted() throws {
    let internalURL = try XCTUnwrap(URL(string: "http://home.local:8123"))
    let unencryptedExternalURL = try XCTUnwrap(URL(string: "http://home.example"))
    for externalURL in [nil, unencryptedExternalURL] {
      let instance = HomeAssistantInstance(
        id: "home", name: "Home", version: nil,
        internalURL: internalURL, externalURL: externalURL, isOnboarding: false
      )

      let candidate = HomeAssistantServerSelection.candidate(from: instance)

      XCTAssertEqual(candidate?.activeURL, internalURL)
    }
  }
}

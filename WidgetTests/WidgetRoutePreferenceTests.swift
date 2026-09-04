import XCTest

final class WidgetRoutePreferenceTests: XCTestCase {
  func testSourceIdentifierPreservesCaseSensitiveURLPath() throws {
    let uppercasePath = try XCTUnwrap(URL(string: "https://HOME.example/HA"))
    let lowercasePath = try XCTUnwrap(URL(string: "HTTPS://home.example/ha"))

    XCTAssertNotEqual(
      BruceSharedHomeAssistant.sourceIdentifier(
        instanceID: nil,
        internalURL: uppercasePath,
        externalURL: nil
      ),
      BruceSharedHomeAssistant.sourceIdentifier(
        instanceID: nil,
        internalURL: lowercasePath,
        externalURL: nil
      )
    )
  }

  func testPreferredRouteIsScopedToItsHomeAssistantSource() throws {
    defer { BruceSharedHomeAssistant.clearWidgetRoute() }
    let route = try XCTUnwrap(URL(string: "https://old.example"))

    BruceSharedHomeAssistant.rememberWidgetRoute(route, for: "old-source")

    XCTAssertEqual(BruceSharedHomeAssistant.preferredWidgetRoute(for: "old-source"), route)
    XCTAssertNil(BruceSharedHomeAssistant.preferredWidgetRoute(for: "replacement-source"))
  }

  func testCandidateURLsDiscardRemovedPreferredRouteForSameInstance() throws {
    defer { BruceSharedHomeAssistant.clearWidgetRoute() }
    let removedRoute = try XCTUnwrap(URL(string: "https://old.example"))
    let currentRoute = try XCTUnwrap(URL(string: "https://new.example"))
    let credentials = WidgetHomeAssistantCredentials(
      schemaVersion: 1,
      instanceID: "same-instance",
      instanceName: "Home",
      internalURL: currentRoute,
      externalURL: nil,
      lastSuccessfulURL: removedRoute,
      accessToken: "access-token",
      refreshToken: "refresh-token",
      tokenType: "Bearer",
      accessTokenExpiresAt: .distantFuture,
      clientID: try XCTUnwrap(URL(string: "https://bruce.example"))
    )
    BruceSharedHomeAssistant.rememberWidgetRoute(
      removedRoute,
      for: credentials.sourceIdentifier
    )

    XCTAssertEqual(credentials.candidateURLs, [currentRoute])
  }
}

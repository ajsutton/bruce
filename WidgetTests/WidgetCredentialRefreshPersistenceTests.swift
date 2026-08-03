import XCTest

final class WidgetCredentialRefreshPersistenceTests: XCTestCase {
  override func tearDown() {
    WidgetTestURLProtocol.router.reset()
    super.tearDown()
  }

  func testConsecutiveLoadsPersistRefreshedCredentials() async throws {
    WidgetTestURLProtocol.router.install { request in
      if request.url?.path == "/auth/token" {
        return .response(
          status: 200,
          data: Data(
            #"{"access_token":"new-token","refresh_token":"rotated-token","expires_in":3600}"#
              .utf8
          )
        )
      }
      return .response(
        status: 200,
        data: Data(
          #"[{"entity_id":"sensor.sigen_plant_battery_state_of_charge","state":"78"}]"#
            .utf8
        )
      )
    }
    let credentials = try expiredCredentials()
    let box = CredentialBox(credentials)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WidgetTestURLProtocol.self]
    let client = WidgetHomeEnergyClient(
      session: URLSession(configuration: configuration),
      now: { Date(timeIntervalSince1970: 10_000) },
      loadCredentials: { box.value },
      persistCredentials: { refreshed, original in
        box.replace(refreshed, ifCurrentIs: original)
      },
      loadDailyTotals: { _ in
        WidgetDailyEnergyTotals(importCostDollars: nil, feedInEarningsDollars: nil)
      }
    )

    _ = try await client.loadSnapshot()
    _ = try await client.loadSnapshot()

    XCTAssertEqual(
      WidgetTestURLProtocol.router.requestedPaths.filter { $0 == "/auth/token" }.count,
      1
    )
    XCTAssertEqual(box.value.refreshToken, "rotated-token")
  }

  func testRefreshCannotReplaceCredentialsForAnotherSource() throws {
    let original = try expiredCredentials()
    let replacementHome = try expiredCredentials(baseURL: "https://other.example")
    let box = CredentialBox(replacementHome)
    var refreshed = original
    refreshed.accessToken = "widget-token"

    box.replace(refreshed, ifCurrentIs: original)

    XCTAssertEqual(box.value, replacementHome)
  }

  func testRefreshCannotReplaceNewerCredentialsForTheSameSource() throws {
    let original = try expiredCredentials()
    var newer = original
    newer.accessToken = "newer-app-token"
    let box = CredentialBox(newer)
    var refreshed = original
    refreshed.accessToken = "widget-token"

    box.replace(refreshed, ifCurrentIs: original)

    XCTAssertEqual(box.value, newer)
  }

  private func expiredCredentials(
    baseURL: String = "http://internal.local"
  ) throws -> WidgetHomeAssistantCredentials {
    let url = try XCTUnwrap(URL(string: baseURL))
    return WidgetHomeAssistantCredentials(
      schemaVersion: 1,
      instanceID: nil,
      instanceName: "Home",
      internalURL: url,
      externalURL: nil,
      lastSuccessfulURL: url,
      accessToken: "old-token",
      refreshToken: "refresh-token",
      tokenType: "Bearer",
      accessTokenExpiresAt: .distantPast,
      clientID: try XCTUnwrap(URL(string: "https://bruce.example"))
    )
  }
}

private final class CredentialBox: @unchecked Sendable {
  private let lock = NSLock()
  private var credentials: WidgetHomeAssistantCredentials

  init(_ credentials: WidgetHomeAssistantCredentials) {
    self.credentials = credentials
  }

  var value: WidgetHomeAssistantCredentials {
    lock.withLock { credentials }
  }

  func replace(
    _ replacement: WidgetHomeAssistantCredentials,
    ifCurrentIs original: WidgetHomeAssistantCredentials
  ) {
    lock.withLock {
      guard credentials == original else { return }
      credentials = replacement
    }
  }
}

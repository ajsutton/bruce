import XCTest

final class WidgetHomeEnergyClientTests: XCTestCase {
  override func setUp() {
    BruceSharedHomeAssistant.clearWidgetRoute()
    BruceSharedHomeAssistant.storeSourceIdentifier(nil)
    super.setUp()
  }

  override func tearDown() {
    WidgetTestURLProtocol.router.reset()
    BruceSharedHomeAssistant.clearWidgetRoute()
    BruceSharedHomeAssistant.storeSourceIdentifier(nil)
    super.tearDown()
  }

  func testSnapshotMapsCurrentReadingsAndDailyTotals() throws {
    let timestamp = Date(timeIntervalSince1970: 1_000)
    let states = [
      try state("sensor.sigen_plant_pv_power", "6.4"),
      try state("sensor.sigen_plant_battery_state_of_charge", "78"),
      try state("sensor.sigen_plant_consumed_power", "2.1"),
      try state("sensor.sigen_plant_grid_active_power", "-3.2"),
      try state("sensor.01krmdgkh60wyckeepvgtbbgv3_general_price", "0.284"),
      try state("sensor.01krmdgkh60wyckeepvgtbbgv3_feed_in_price", "0.08"),
    ]

    let snapshot = WidgetHomeEnergyClient.snapshot(
      from: states,
      totals: WidgetDailyEnergyTotals(
        importCostDollars: 2.43,
        feedInEarningsDollars: 4.18
      ),
      capturedAt: timestamp
    )

    XCTAssertEqual(snapshot.capturedAt, timestamp)
    XCTAssertEqual(snapshot.pvPowerKilowatts, 6.4)
    XCTAssertEqual(snapshot.batteryStateOfCharge, 78)
    XCTAssertEqual(snapshot.homeConsumptionKilowatts, 2.1)
    XCTAssertEqual(snapshot.gridPowerKilowatts, -3.2)
    XCTAssertEqual(snapshot.generalPriceDollarsPerKilowattHour, 0.284)
    XCTAssertEqual(snapshot.feedInPriceDollarsPerKilowattHour, 0.08)
    XCTAssertEqual(snapshot.importCostTodayDollars, 2.43)
    XCTAssertEqual(snapshot.feedInEarningsTodayDollars, 4.18)
  }

  func testCurrentReadingsSurviveDailyTotalsFailure() throws {
    let previous = HomeEnergyWidgetSnapshot(
      capturedAt: Date(timeIntervalSince1970: 500),
      pvPowerKilowatts: 1,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: 1,
      gridPowerKilowatts: 0,
      generalPriceDollarsPerKilowattHour: 0.2,
      feedInPriceDollarsPerKilowattHour: 0.08,
      importCostTodayDollars: 2.43,
      feedInEarningsTodayDollars: 4.18,
      dailyEnergyInterval: DateInterval(
        start: Date(timeIntervalSince1970: 0),
        end: Date(timeIntervalSince1970: 86_400)
      )
    )

    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: [
          try state("sensor.sigen_plant_battery_state_of_charge", "78")
        ],
        currentTotals: nil,
        previous: previous,
        capturedAt: Date(timeIntervalSince1970: 1_000)
      )
    )

    XCTAssertEqual(snapshot.batteryStateOfCharge, 78)
    XCTAssertTrue(snapshot.readingsAreCurrent)
    XCTAssertEqual(snapshot.importCostTodayDollars, 2.43)
    XCTAssertEqual(snapshot.feedInEarningsTodayDollars, 4.18)
    XCTAssertFalse(snapshot.importCostIsCurrent)
    XCTAssertFalse(snapshot.feedInEarningsIsCurrent)
    XCTAssertEqual(snapshot.importCostCapturedAt, Date(timeIntervalSince1970: 500))
  }

  func testCurrentTotalsSurviveReadingsFailure() throws {
    let previous = HomeEnergyWidgetSnapshot(
      capturedAt: Date(timeIntervalSince1970: 500),
      pvPowerKilowatts: 1,
      batteryStateOfCharge: 50,
      homeConsumptionKilowatts: 1,
      gridPowerKilowatts: 0,
      generalPriceDollarsPerKilowattHour: 0.2,
      feedInPriceDollarsPerKilowattHour: 0.08,
      importCostTodayDollars: 1,
      feedInEarningsTodayDollars: 1,
      dailyEnergyInterval: DateInterval(
        start: Date(timeIntervalSince1970: 0),
        end: Date(timeIntervalSince1970: 86_400)
      )
    )

    let snapshot = try XCTUnwrap(
      WidgetHomeEnergyClient.snapshot(
        currentStates: nil,
        currentTotals: WidgetDailyEnergyTotals(
          importCostDollars: 2.43,
          feedInEarningsDollars: 4.18
        ),
        previous: previous,
        capturedAt: Date(timeIntervalSince1970: 1_000)
      )
    )

    XCTAssertEqual(snapshot.batteryStateOfCharge, 50)
    XCTAssertFalse(snapshot.readingsAreCurrent)
    XCTAssertEqual(snapshot.importCostTodayDollars, 2.43)
    XCTAssertTrue(snapshot.importCostIsCurrent)
    XCTAssertEqual(snapshot.readingsCapturedAt, Date(timeIntervalSince1970: 500))
  }

  func testMalformedInternalStatesFallBackToExternalRoute() async throws {
    WidgetTestURLProtocol.router.install { request in
      if request.url?.host == "internal.local" {
        return .response(status: 200, data: Data("not-json".utf8))
      }
      return .response(
        status: 200,
        data: Data(
          #"[{"entity_id":"sensor.sigen_plant_battery_state_of_charge","state":"78"}]"#
            .utf8
        )
      )
    }
    let credentials = try credentials(withExternalURL: true)
    BruceSharedHomeAssistant.storeSourceIdentifier(credentials.sourceIdentifier)
    let client = makeClient(credentials: credentials)

    let firstSnapshot = try await client.loadSnapshot()
    let secondSnapshot = try await client.loadSnapshot()

    XCTAssertEqual(firstSnapshot.batteryStateOfCharge, 78)
    XCTAssertEqual(secondSnapshot.batteryStateOfCharge, 78)
    XCTAssertEqual(
      WidgetTestURLProtocol.router.requestedHosts,
      ["internal.local", "external.example", "external.example"]
    )
  }

  func testExpiredAccessTokenRefreshesBeforeLoadingStates() async throws {
    WidgetTestURLProtocol.router.install { request in
      if request.url?.path == "/auth/token" {
        return .response(
          status: 200,
          data: Data(#"{"access_token":"new-token","expires_in":3600}"#.utf8)
        )
      }
      let token = request.value(forHTTPHeaderField: "Authorization")
      let state = token == "Bearer new-token" ? "78" : "12"
      return .response(
        status: 200,
        data: Data(
          "[{\"entity_id\":\"sensor.sigen_plant_battery_state_of_charge\",\"state\":\"\(state)\"}]"
            .utf8
        )
      )
    }
    var credentials = try credentials()
    credentials.accessTokenExpiresAt = .distantPast

    let snapshot = try await makeClient(credentials: credentials).loadSnapshot()

    XCTAssertEqual(snapshot.batteryStateOfCharge, 78)
    XCTAssertEqual(WidgetTestURLProtocol.router.requestedPaths.first, "/auth/token")
  }

  func testUnauthorizedStatesRefreshTokenAndRetry() async throws {
    WidgetTestURLProtocol.router.install { request in
      if request.url?.path == "/auth/token" {
        return .response(
          status: 200,
          data: Data(#"{"access_token":"new-token","expires_in":3600}"#.utf8)
        )
      }
      guard request.value(forHTTPHeaderField: "Authorization") == "Bearer new-token" else {
        return .response(status: 401, data: Data())
      }
      return .response(
        status: 200,
        data: Data(
          #"[{"entity_id":"sensor.sigen_plant_battery_state_of_charge","state":"78"}]"#
            .utf8
        )
      )
    }

    let snapshot = try await makeClient(credentials: try credentials()).loadSnapshot()

    XCTAssertEqual(snapshot.batteryStateOfCharge, 78)
    XCTAssertEqual(
      WidgetTestURLProtocol.router.requestedPaths,
      ["/api/states", "/auth/token", "/api/states"]
    )
  }

  func testCancellationDoesNotTryTheExternalStatesRoute() async throws {
    WidgetTestURLProtocol.router.install { _ in .blocked }
    let client = makeClient(credentials: try credentials(withExternalURL: true))
    let task = Task {
      try await client.loadSnapshot()
    }
    await fulfillment(of: [WidgetTestURLProtocol.router.requestStarted], timeout: 1)

    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
      XCTAssertEqual(WidgetTestURLProtocol.router.requestedHosts, ["internal.local"])
    }
  }

  private func state(
    _ entityID: String,
    _ value: String,
    lastReset: Date? = nil
  ) throws -> WidgetHomeAssistantState {
    var object: [String: Any] = ["entity_id": entityID, "state": value]
    if let lastReset {
      object["attributes"] = ["last_reset": lastReset.formatted(.iso8601)]
    }
    let data = try JSONSerialization.data(
      withJSONObject: object
    )
    return try JSONDecoder().decode(
      WidgetHomeAssistantState.self,
      from: data
    )
  }

  private func makeClient(
    credentials: WidgetHomeAssistantCredentials
  ) -> WidgetHomeEnergyClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WidgetTestURLProtocol.self]
    return WidgetHomeEnergyClient(
      session: URLSession(configuration: configuration),
      now: { Date(timeIntervalSince1970: 10_000) },
      loadCredentials: { credentials },
      loadDailyTotals: { _ in
        WidgetDailyEnergyTotals(importCostDollars: 2.43, feedInEarningsDollars: 4.18)
      }
    )
  }

  private func credentials(
    withExternalURL: Bool = false
  ) throws -> WidgetHomeAssistantCredentials {
    let internalURL = try XCTUnwrap(URL(string: "http://internal.local"))
    return WidgetHomeAssistantCredentials(
      schemaVersion: 1,
      instanceID: nil,
      instanceName: "Home",
      internalURL: internalURL,
      externalURL:
        withExternalURL ? URL(string: "https://external.example") : nil,
      lastSuccessfulURL: internalURL,
      accessToken: "old-token",
      refreshToken: "refresh-token",
      tokenType: "Bearer",
      accessTokenExpiresAt: .distantFuture,
      clientID: try XCTUnwrap(URL(string: "https://bruce.example"))
    )
  }
}

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

enum WidgetTestURLAction: Sendable {
  case response(status: Int, data: Data)
  case blocked
}

final class WidgetTestURLRouter: @unchecked Sendable {
  let requestStarted = XCTestExpectation(description: "URL request started")

  private let lock = NSLock()
  private var handler: (@Sendable (URLRequest) -> WidgetTestURLAction)?
  private var requests: [URLRequest] = []

  var requestedHosts: [String] {
    lock.withLock { requests.compactMap { $0.url?.host } }
  }

  var requestedPaths: [String] {
    lock.withLock { requests.compactMap { $0.url?.path } }
  }

  func install(_ handler: @escaping @Sendable (URLRequest) -> WidgetTestURLAction) {
    lock.withLock {
      self.handler = handler
      requests = []
    }
  }

  func action(for request: URLRequest) -> WidgetTestURLAction {
    lock.withLock {
      requests.append(request)
      return handler?(request) ?? .response(status: 500, data: Data())
    }
  }

  func reset() {
    lock.withLock {
      handler = nil
      requests = []
    }
  }
}

final class WidgetTestURLProtocol: URLProtocol, @unchecked Sendable {
  static let router = WidgetTestURLRouter()

  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    switch Self.router.action(for: request) {
    case .response(let status, let data):
      guard let url = request.url,
        let response = HTTPURLResponse(
          url: url,
          statusCode: status,
          httpVersion: nil,
          headerFields: nil
        )
      else { return }
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    case .blocked:
      Self.router.requestStarted.fulfill()
    }
  }

  override func stopLoading() {}
}

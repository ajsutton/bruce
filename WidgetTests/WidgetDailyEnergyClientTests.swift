import XCTest

final class WidgetDailyEnergyClientTests: XCTestCase {
  func testTotalsSelectStatisticsContainingTheRefreshTime() throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let data = try JSONSerialization.data(
      withJSONObject: [
        "id": 1,
        "type": "result",
        "success": true,
        "result": [
          "sensor.sigen_plant_total_imported_energy_cost": [
            statistic(start: 9_000, end: 11_000, change: 2.43)
          ],
          "sensor.sigen_plant_total_exported_energy_compensation": [
            statistic(start: 9_000, end: 11_000, change: 4.18)
          ],
        ],
      ]
    )

    let totals = try WidgetDailyEnergyClient.totals(from: data, at: timestamp)

    XCTAssertEqual(totals.importCostDollars, 2.43)
    XCTAssertEqual(totals.feedInEarningsDollars, 4.18)
    XCTAssertEqual(
      totals.interval,
      DateInterval(
        start: timestamp.addingTimeInterval(-1_000), end: timestamp.addingTimeInterval(1_000)))
  }

  func testTotalsRejectMalformedStatisticsResponse() throws {
    let data = try JSONSerialization.data(
      withJSONObject: ["id": 1, "type": "result", "success": false]
    )

    XCTAssertThrowsError(
      try WidgetDailyEnergyClient.totals(from: data, at: Date())
    )
  }

  func testTotalsRejectDifferentCalendarIntervals() throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let data = try JSONSerialization.data(
      withJSONObject: [
        "id": 1,
        "type": "result",
        "success": true,
        "result": [
          "sensor.sigen_plant_total_imported_energy_cost": [
            statistic(start: 9_000, end: 11_000, change: 2.43)
          ],
          "sensor.sigen_plant_total_exported_energy_compensation": [
            statistic(start: 9_100, end: 11_000, change: 4.18)
          ],
        ],
      ]
    )

    XCTAssertThrowsError(
      try WidgetDailyEnergyClient.totals(from: data, at: timestamp)
    )
  }

  func testTotalsMarkAMissingSingleStatisticStale() throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let data = try JSONSerialization.data(
      withJSONObject: [
        "id": 1,
        "type": "result",
        "success": true,
        "result": [
          "sensor.sigen_plant_total_imported_energy_cost": [
            statistic(start: 9_000, end: 11_000, change: 2.43)
          ]
        ],
      ]
    )

    let totals = try WidgetDailyEnergyClient.totals(from: data, at: timestamp)

    XCTAssertTrue(totals.importIsCurrent)
    XCTAssertFalse(totals.feedInIsCurrent)
  }

  func testTotalsMarkStatisticWithoutChangeStale() throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let data = try JSONSerialization.data(
      withJSONObject: [
        "id": 1,
        "type": "result",
        "success": true,
        "result": [
          "sensor.sigen_plant_total_imported_energy_cost": [
            statistic(start: 9_000, end: 11_000, change: nil)
          ]
        ],
      ]
    )

    let totals = try WidgetDailyEnergyClient.totals(from: data, at: timestamp)

    XCTAssertNil(totals.importCostDollars)
    XCTAssertFalse(totals.importIsCurrent)
  }

  func testTimeoutClosesBlockedWebSocket() async throws {
    let connection = WidgetTestEnergyConnection(messages: [
      Data(#"{"type":"auth_required"}"#.utf8),
      Data(#"{"type":"auth_ok"}"#.utf8),
    ])
    let timeout = WidgetTestTimeoutGate()
    let client = WidgetDailyEnergyClient(
      connect: { _ in connection },
      now: { Date(timeIntervalSince1970: 10_000) },
      waitForTimeout: { try await timeout.wait() }
    )
    let credentials = try credentials()
    let task = Task {
      try await client.loadTotals(using: credentials)
    }
    await fulfillment(of: [connection.blockedReceiveStarted], timeout: 1)

    timeout.fire()

    do {
      _ = try await task.value
      XCTFail("Expected the statistics request to time out.")
    } catch WidgetHomeEnergyError.noReachableServer {
      XCTAssertEqual(connection.cancelCount, 1)
    }
  }

  func testCancellationClosesWebSocketWithoutTryingAnotherRoute() async throws {
    let connection = WidgetTestEnergyConnection(messages: [
      Data(#"{"type":"auth_required"}"#.utf8),
      Data(#"{"type":"auth_ok"}"#.utf8),
    ])
    let connector = WidgetTestEnergyConnector(connection: connection)
    let timeout = WidgetTestTimeoutGate()
    let client = WidgetDailyEnergyClient(
      connect: { connector.connect(to: $0) },
      now: { Date(timeIntervalSince1970: 10_000) },
      waitForTimeout: { try await timeout.wait() }
    )
    let credentials = try credentials(withExternalURL: true)
    let task = Task {
      try await client.loadTotals(using: credentials)
    }
    await fulfillment(of: [connection.blockedReceiveStarted], timeout: 1)

    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation.")
    } catch is CancellationError {
      XCTAssertEqual(connection.cancelCount, 1)
      XCTAssertEqual(connector.connectedURLs.count, 1)
    }
  }

  private func statistic(
    start: TimeInterval,
    end: TimeInterval,
    change: Double?
  ) -> [String: Any] {
    [
      "start": start * 1_000,
      "end": end * 1_000,
      "change": change ?? NSNull(),
    ]
  }

  private func credentials(
    withExternalURL: Bool = false
  ) throws -> WidgetHomeAssistantCredentials {
    let internalURL = try XCTUnwrap(URL(string: "http://home.local"))
    return WidgetHomeAssistantCredentials(
      schemaVersion: 1,
      instanceID: nil,
      instanceName: "Home",
      internalURL: internalURL,
      externalURL: withExternalURL ? URL(string: "https://home.example") : nil,
      lastSuccessfulURL: internalURL,
      accessToken: "token",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: .distantFuture,
      clientID: try XCTUnwrap(URL(string: "https://bruce.example"))
    )
  }
}

private final class WidgetTestEnergyConnection:
  WidgetEnergyWebSocketConnection,
  @unchecked Sendable
{
  let blockedReceiveStarted = XCTestExpectation(description: "WebSocket receive blocked")

  private let lock = NSLock()
  private var messages: [Data]
  private var receiveContinuation: CheckedContinuation<Data, Error>?
  private var cancellationCount = 0
  private var isCancelled = false

  init(messages: [Data]) {
    self.messages = messages
  }

  var cancelCount: Int { lock.withLock { cancellationCount } }

  func resume() {}

  func send(_ data: Data) async throws {}

  func receive() async throws -> Data {
    if let message = lock.withLock({ messages.isEmpty ? nil : messages.removeFirst() }) {
      return message
    }
    blockedReceiveStarted.fulfill()
    return try await withCheckedThrowingContinuation { continuation in
      let shouldCancel = lock.withLock {
        if isCancelled { return true }
        receiveContinuation = continuation
        return false
      }
      if shouldCancel { continuation.resume(throwing: CancellationError()) }
    }
  }

  func cancel() {
    let continuation: CheckedContinuation<Data, Error>? = lock.withLock {
      guard cancellationCount == 0 else { return nil }
      cancellationCount = 1
      isCancelled = true
      let continuation = receiveContinuation
      receiveContinuation = nil
      return continuation
    }
    continuation?.resume(throwing: CancellationError())
  }
}

private final class WidgetTestEnergyConnector: @unchecked Sendable {
  private let lock = NSLock()
  private let connection: WidgetTestEnergyConnection
  private var urls: [URL] = []

  init(connection: WidgetTestEnergyConnection) {
    self.connection = connection
  }

  var connectedURLs: [URL] { lock.withLock { urls } }

  func connect(to url: URL) -> any WidgetEnergyWebSocketConnection {
    lock.withLock { urls.append(url) }
    return connection
  }
}

private final class WidgetTestTimeoutGate: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Error>?
  private var pendingError: Error?

  func wait() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let pendingError: Error? = lock.withLock {
          if let pendingError = self.pendingError {
            self.pendingError = nil
            return pendingError
          }
          self.continuation = continuation
          return nil
        }
        if let pendingError { continuation.resume(throwing: pendingError) }
      }
    } onCancel: {
      cancel()
    }
  }

  func fire() {
    finish(with: WidgetHomeEnergyError.noReachableServer)
  }

  private func cancel() {
    finish(with: CancellationError())
  }

  private func finish(with error: Error) {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      if continuation == nil { pendingError = error }
      return continuation
    }
    continuation?.resume(throwing: error)
  }
}

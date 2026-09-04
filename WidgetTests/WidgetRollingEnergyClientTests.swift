import XCTest

final class WidgetRollingEnergyClientTests: XCTestCase {
  func testTotalsPackageRollingAggregates() throws {
    let totals = try WidgetRollingEnergyClient.totals(
      importCost: 2.43,
      feedInEarnings: 4.18
    )

    XCTAssertEqual(totals.importCostDollars, 2.43)
    XCTAssertEqual(totals.feedInEarningsDollars, 4.18)
  }

  func testTotalsRejectResponseWithoutEitherAggregate() {
    XCTAssertThrowsError(
      try WidgetRollingEnergyClient.totals(
        importCost: nil,
        feedInEarnings: nil
      )
    )
  }

  func testTotalsMarkAMissingAggregateStale() throws {
    let totals = try WidgetRollingEnergyClient.totals(
      importCost: 2.43,
      feedInEarnings: nil
    )

    XCTAssertTrue(totals.importIsCurrent)
    XCTAssertFalse(totals.feedInIsCurrent)
  }

  func testLoadingUsesCounterCutoffForABucketAlignedRollingWindow() async throws {
    let timestamp = Date(timeIntervalSince1970: 100_201)
    let counterResponse = try JSONSerialization.data(
      withJSONObject: [
        "id": 1,
        "type": "result",
        "success": true,
        "result": [
          "sensor.sigen_plant_total_imported_energy_cost": [
            counterStatistic(start: 99_600, end: 99_900, state: 12)
          ],
          "sensor.sigen_plant_total_exported_energy_compensation": [
            counterStatistic(start: 99_600, end: 99_900, state: 24)
          ],
        ],
      ]
    )
    let connection = WidgetTestEnergyConnection(messages: [
      Data(#"{"type":"auth_required"}"#.utf8),
      Data(#"{"type":"auth_ok"}"#.utf8),
      counterResponse,
      try totalResponse(id: 2, change: 2.43),
      try totalResponse(id: 3, change: 4.18),
    ])
    let timeout = WidgetTestTimeoutGate()
    let client = WidgetRollingEnergyClient(
      connect: { _ in connection },
      now: { timestamp },
      waitForTimeout: { try await timeout.wait() }
    )

    _ = try await client.loadTotals(using: credentials())

    try assertRollingStatisticsRequests(connection.sentMessageJSON, at: timestamp)
  }

  func testTimeoutClosesBlockedWebSocket() async throws {
    let connection = WidgetTestEnergyConnection(messages: [
      Data(#"{"type":"auth_required"}"#.utf8),
      Data(#"{"type":"auth_ok"}"#.utf8),
    ])
    let timeout = WidgetTestTimeoutGate()
    let client = WidgetRollingEnergyClient(
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

  func testOverlappingCounterBucketsAreRejectedBeforeAggregateRequests() async throws {
    let response = try JSONSerialization.data(
      withJSONObject: [
        "id": 1,
        "type": "result",
        "success": true,
        "result": [
          "sensor.sigen_plant_total_imported_energy_cost": [
            counterStatistic(start: 99_600, end: 99_900, state: 12),
            counterStatistic(start: 99_750, end: 100_000, state: 13),
          ]
        ],
      ]
    )
    let connection = WidgetTestEnergyConnection(messages: [
      Data(#"{"type":"auth_required"}"#.utf8),
      Data(#"{"type":"auth_ok"}"#.utf8),
      response,
    ])
    let client = WidgetRollingEnergyClient(
      connect: { _ in connection },
      now: { Date(timeIntervalSince1970: 100_200) },
      waitForTimeout: { try await WidgetTestTimeoutGate().wait() }
    )

    do {
      _ = try await client.loadTotals(using: credentials())
      XCTFail("Expected overlapping recorder buckets to be rejected.")
    } catch WidgetHomeEnergyError.noReachableServer {
      XCTAssertEqual(connection.sentMessageJSON.count, 2)
    }
  }

  func testFutureCounterBucketIsRejectedBeforeAggregateRequests() async throws {
    let response = try JSONSerialization.data(
      withJSONObject: [
        "id": 1,
        "type": "result",
        "success": true,
        "result": [
          "sensor.sigen_plant_total_imported_energy_cost": [
            counterStatistic(start: 99_000, end: 100_300, state: 12)
          ]
        ],
      ]
    )
    let connection = WidgetTestEnergyConnection(messages: [
      Data(#"{"type":"auth_required"}"#.utf8),
      Data(#"{"type":"auth_ok"}"#.utf8),
      response,
    ])
    let client = WidgetRollingEnergyClient(
      connect: { _ in connection },
      now: { Date(timeIntervalSince1970: 100_000) },
      waitForTimeout: { try await WidgetTestTimeoutGate().wait() }
    )

    do {
      _ = try await client.loadTotals(using: credentials())
      XCTFail("Expected a future recorder bucket to be rejected.")
    } catch WidgetHomeEnergyError.noReachableServer {
      XCTAssertEqual(connection.sentMessageJSON.count, 2)
    }
  }

  func testCancellationClosesWebSocketWithoutTryingAnotherRoute() async throws {
    let connection = WidgetTestEnergyConnection(messages: [
      Data(#"{"type":"auth_required"}"#.utf8),
      Data(#"{"type":"auth_ok"}"#.utf8),
    ])
    let connector = WidgetTestEnergyConnector(connection: connection)
    let timeout = WidgetTestTimeoutGate()
    let client = WidgetRollingEnergyClient(
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

  private func counterStatistic(
    start: TimeInterval,
    end: TimeInterval,
    state: Double
  ) -> [String: Any] {
    [
      "start": start * 1_000,
      "end": end * 1_000,
      "state": state,
      "last_reset": 1_000,
    ]
  }

  private func totalResponse(id: Int, change: Double) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: [
        "id": id,
        "type": "result",
        "success": true,
        "result": ["change": change],
      ]
    )
  }

  private func assertRollingStatisticsRequests(
    _ requestJSON: [[String: Any]],
    at timestamp: Date
  ) throws {
    let counterRequest = try XCTUnwrap(
      requestJSON.first { $0["type"] as? String == "recorder/statistics_during_period" }
    )
    XCTAssertEqual(
      counterRequest["start_time"] as? String,
      timestamp.addingTimeInterval(-15 * 60).formatted(.iso8601)
    )
    XCTAssertEqual(counterRequest["end_time"] as? String, timestamp.formatted(.iso8601))
    XCTAssertEqual(counterRequest["period"] as? String, "5minute")
    XCTAssertEqual(counterRequest["types"] as? [String], ["state"])
    let totalRequests = requestJSON.filter {
      $0["type"] as? String == "recorder/statistic_during_period"
    }
    XCTAssertEqual(totalRequests.count, 2)
    for request in totalRequests {
      XCTAssertEqual(
        request["start_time"] as? String,
        Date(timeIntervalSince1970: 13_500).formatted(.iso8601)
      )
      XCTAssertEqual(
        request["end_time"] as? String,
        Date(timeIntervalSince1970: 99_900).formatted(.iso8601)
      )
      XCTAssertEqual(request["types"] as? [String], ["change"])
    }
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
  private var sentMessages: [Data] = []

  init(messages: [Data]) {
    self.messages = messages
  }

  var cancelCount: Int { lock.withLock { cancellationCount } }

  var sentMessageJSON: [[String: Any]] {
    lock.withLock {
      sentMessages.compactMap {
        try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
      }
    }
  }

  func resume() {}

  func send(_ data: Data) async throws {
    lock.withLock { sentMessages.append(data) }
  }

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

import XCTest

@testable import Bruce

final class RollingEnergyTotalsClientTests: XCTestCase {
  func testLoadingRollingTotalsUsesTwentyFourHoursOfFiveMinuteBuckets() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let timestamp = Date(timeIntervalSince1970: 1_785_463_201)
    let connection = TemperatureSubscriptionConnection(messages: [
      .success(#"{"type":"auth_required"}"#),
      .success(#"{"type":"auth_ok"}"#),
      .success(statisticsResponse),
      .success(totalResponse(change: 0.1959)),
      .success(totalResponse(change: 0.9086)),
    ])
    let connector = TemperatureSubscriptionConnector(connections: [connection])

    let totals = try await HomeAssistantRollingEnergyTotalsClient(
      commands: TestWebSocketCommands(session: session, connector: connector),
      now: { timestamp }
    ).loadRollingEnergyTotals()

    XCTAssertEqual(totals.importCostDollars, 0.1959)
    XCTAssertEqual(totals.feedInEarningsDollars, 0.9086)
    XCTAssertEqual(totals.refreshAfter, timestamp.addingTimeInterval(15 * 60))
    XCTAssertEqual(
      connection.sentMessageTypes,
      [
        "auth",
        "recorder/statistics_during_period",
        "recorder/statistic_during_period",
        "recorder/statistic_during_period",
      ]
    )
    try assertRollingStatisticsRequest(
      connection.sentMessageJSON,
      at: timestamp
    )
  }

  private func assertRollingStatisticsRequest(
    _ requestJSON: [[String: Any]],
    at timestamp: Date
  ) throws {
    let counterRequest = try XCTUnwrap(
      requestJSON.first { $0["type"] as? String == "recorder/statistics_during_period" }
    )
    let totalRequests = requestJSON.filter {
      $0["type"] as? String == "recorder/statistic_during_period"
    }
    let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    XCTAssertEqual(
      counterRequest["start_time"] as? String,
      timestamp.addingTimeInterval(-15 * 60).formatted(timestampStyle)
    )
    XCTAssertEqual(
      counterRequest["end_time"] as? String,
      timestamp.formatted(timestampStyle)
    )
    XCTAssertEqual(counterRequest["period"] as? String, "5minute")
    XCTAssertEqual(
      counterRequest["types"] as? [String],
      ["state"]
    )
    XCTAssertEqual(totalRequests.count, 2)
    for request in totalRequests {
      let fixedPeriod = try XCTUnwrap(request["fixed_period"] as? [String: String])
      XCTAssertEqual(
        fixedPeriod["end_time"],
        timestamp.addingTimeInterval(-301).formatted(timestampStyle)
      )
      XCTAssertEqual(
        fixedPeriod["start_time"],
        timestamp.addingTimeInterval(-24 * 60 * 60 - 301).formatted(timestampStyle)
      )
      XCTAssertNil(request["start_time"])
      XCTAssertNil(request["end_time"])
      XCTAssertEqual(request["types"] as? [String], ["change"])
    }
  }

  func testCancellingBlockedStatisticsReceiveClosesConnection() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connection = TemperatureSubscriptionConnection(messages: [
      .success(#"{"type":"auth_required"}"#),
      .success(#"{"type":"auth_ok"}"#),
    ])
    let client = HomeAssistantRollingEnergyTotalsClient(
      commands: TestWebSocketCommands(
        session: session,
        connector: TemperatureSubscriptionConnector(connections: [connection])
      )
    )
    let task = Task {
      try await client.loadRollingEnergyTotals()
    }
    await fulfillment(of: [connection.blockedReceiveStarted], timeout: 1)

    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected the rolling statistics request to be cancelled.")
    } catch is CancellationError {
      XCTAssertTrue(connection.isCancelled)
    }
  }

  func testCancellationBeforeConnectDoesNotOpenWebSocket() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connection = TemperatureSubscriptionConnection(messages: [])
    let connector = TemperatureSubscriptionConnector(connections: [connection])
    let gate = RollingEnergyCancellationGate()
    let client = HomeAssistantRollingEnergyTotalsClient(
      commands: TestWebSocketCommands(session: session, connector: connector)
    )
    let task = Task {
      await gate.wait()
      return try await client.loadRollingEnergyTotals()
    }
    await fulfillment(of: [gate.started], timeout: 1)

    task.cancel()
    gate.open()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation before opening a WebSocket.")
    } catch is CancellationError {
      XCTAssertTrue(connector.connectedURLs.isEmpty)
    }
  }

  func testFutureCounterBucketIsRejectedBeforeAggregateRequests() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connection = TemperatureSubscriptionConnection(messages: [
      .success(#"{"type":"auth_required"}"#),
      .success(#"{"type":"auth_ok"}"#),
      .success(
        """
        {"id":1,"type":"result","success":true,"result":{
          "\(HomeAssistantHomeEnergySnapshot.importCostEntityID)":[
            {"start":99900000,"end":100300000,"state":12}
          ]
        }}
        """
      ),
    ])
    let client = HomeAssistantRollingEnergyTotalsClient(
      commands: TestWebSocketCommands(
        session: session,
        connector: TemperatureSubscriptionConnector(connections: [connection])
      ),
      now: { Date(timeIntervalSince1970: 100_000) }
    )

    do {
      _ = try await client.loadRollingEnergyTotals()
      XCTFail("Expected a future recorder bucket to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
      // Expected.
    }
    XCTAssertEqual(
      connection.sentMessageTypes,
      ["auth", "recorder/statistics_during_period"]
    )
  }

  func testOverlappingCounterBucketsAreRejectedBeforeAggregateRequests() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let entityID = HomeAssistantHomeEnergySnapshot.importCostEntityID
    let connection = TemperatureSubscriptionConnection(messages: [
      .success(#"{"type":"auth_required"}"#),
      .success(#"{"type":"auth_ok"}"#),
      .success(
        """
        {"id":1,"type":"result","success":true,"result":{
          "\(entityID)":[
            {"start":99600000,"end":99900000,"state":12},
            {"start":99750000,"end":100000000,"state":13}
          ]
        }}
        """
      ),
    ])
    let client = HomeAssistantRollingEnergyTotalsClient(
      commands: TestWebSocketCommands(
        session: session,
        connector: TemperatureSubscriptionConnector(connections: [connection])
      ),
      now: { Date(timeIntervalSince1970: 100_200) }
    )

    do {
      _ = try await client.loadRollingEnergyTotals()
      XCTFail("Expected overlapping recorder buckets to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
      // Expected.
    }
    XCTAssertEqual(
      connection.sentMessageTypes,
      ["auth", "recorder/statistics_during_period"]
    )
  }

  private func totalResponse(change: Double) -> String {
    """
    {"id":2,"type":"result","success":true,"result":{"change":\(change)}}
    """
  }

  private var statisticsResponse: String {
    """
    {
      "id": 1,
      "type": "result",
      "success": true,
      "result": {
        "\(HomeAssistantHomeEnergySnapshot.importCostEntityID)": [
          {
            "start": 1785376800000,
            "end": 1785377100000,
            "change": 0.0759,
            "state": 0.1551,
            "last_reset": 1785301415834
          },
          {
            "start": 1785462600000,
            "end": 1785462900000,
            "change": 0.12,
            "state": 0.2751,
            "last_reset": 1785301415834
          }
        ],
        "\(HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID)": [
          {
            "start": 1785376800000,
            "end": 1785377100000,
            "change": 0.3086,
            "state": 2.5631,
            "last_reset": 1785301415834
          },
          {
            "start": 1785462600000,
            "end": 1785462900000,
            "change": 0.6,
            "state": 3.1631,
            "last_reset": 1785301415834
          }
        ]
      }
    }
    """
  }
}

private final class RollingEnergyCancellationGate: @unchecked Sendable {
  let started = XCTestExpectation(description: "Cancellation gate reached")

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    await withCheckedContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func open() {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume()
  }
}

import XCTest

@testable import Bruce

final class DailyEnergyTotalsClientTests: XCTestCase {
  func testLoadingDailyTotalsRequestsCurrentCalendarDayStatistics() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let timestamp = Date(timeIntervalSince1970: 1_785_463_200)
    let connection = TemperatureSubscriptionConnection(messages: [
      .success(#"{"type":"auth_required"}"#),
      .success(#"{"type":"auth_ok"}"#),
      .success(statisticsResponse),
    ])
    let connector = TemperatureSubscriptionConnector(connections: [connection])

    let totals = try await HomeAssistantDailyEnergyTotalsClient(
      commands: TestWebSocketCommands(session: session, connector: connector),
      now: { timestamp }
    ).loadDailyEnergyTotals()

    XCTAssertEqual(totals.importCostDollars, 0.1959)
    XCTAssertEqual(totals.feedInEarningsDollars, 0.9086)
    XCTAssertEqual(totals.importCounter?.value, 0.2751)
    XCTAssertEqual(totals.feedInCounter?.value, 3.1631)
    XCTAssertEqual(
      totals.interval,
      DateInterval(
        start: Date(timeIntervalSince1970: 1_785_420_000),
        end: Date(timeIntervalSince1970: 1_785_506_400)
      )
    )
    XCTAssertEqual(
      connection.sentMessageTypes,
      ["auth", "recorder/statistics_during_period"]
    )
    let request = try XCTUnwrap(connection.sentMessageJSON.last)
    XCTAssertEqual(request["period"] as? String, "day")
    XCTAssertEqual(
      request["types"] as? [String],
      ["change", "last_reset", "state"]
    )
    XCTAssertEqual(
      Set(request["statistic_ids"] as? [String] ?? []),
      [
        HomeAssistantHomeEnergySnapshot.importCostEntityID,
        HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID,
      ]
    )
  }

  func testDailyTotalsRejectStatisticsWithDifferentCalendarIntervals() throws {
    let timestamp = Date(timeIntervalSince1970: 1_785_463_200)
    let first = try statistic(
      start: 1_785_420_000,
      end: 1_785_506_400,
      change: 0.20
    )
    let second = try statistic(
      start: 1_785_421_000,
      end: 1_785_506_400,
      change: 0.91
    )

    XCTAssertThrowsError(
      try HomeAssistantDailyEnergyTotalsClient.totals(
        from: [
          HomeAssistantHomeEnergySnapshot.importCostEntityID: [first],
          HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID: [second],
        ],
        at: timestamp
      )
    )
  }

  func testCancellingBlockedStatisticsReceiveClosesConnection() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connection = TemperatureSubscriptionConnection(messages: [
      .success(#"{"type":"auth_required"}"#),
      .success(#"{"type":"auth_ok"}"#),
    ])
    let client = HomeAssistantDailyEnergyTotalsClient(
      commands: TestWebSocketCommands(
        session: session,
        connector: TemperatureSubscriptionConnector(connections: [connection])
      )
    )
    let task = Task {
      try await client.loadDailyEnergyTotals()
    }
    await fulfillment(of: [connection.blockedReceiveStarted], timeout: 1)

    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected the daily statistics request to be cancelled.")
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
    let gate = DailyEnergyCancellationGate()
    let client = HomeAssistantDailyEnergyTotalsClient(
      commands: TestWebSocketCommands(session: session, connector: connector)
    )
    let task = Task {
      await gate.wait()
      return try await client.loadDailyEnergyTotals()
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

  private func statistic(
    start: TimeInterval,
    end: TimeInterval,
    change: Double
  ) throws -> HomeAssistantEnergyStatistic {
    try JSONDecoder().decode(
      HomeAssistantEnergyStatistic.self,
      from: Data(
        """
        {"start":\(start * 1_000),"end":\(end * 1_000),"change":\(change)}
        """.utf8
      )
    )
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
            "start": 1785420000000,
            "end": 1785506400000,
            "change": 0.1959,
            "state": 0.2751,
            "last_reset": 1785301415834
          }
        ],
        "\(HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID)": [
          {
            "start": 1785420000000,
            "end": 1785506400000,
            "change": 0.9086,
            "state": 3.1631,
            "last_reset": 1785301415834
          }
        ]
      }
    }
    """
  }
}

private final class DailyEnergyCancellationGate: @unchecked Sendable {
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

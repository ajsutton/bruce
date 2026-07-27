import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantTemperatureReconnectTests: XCTestCase {
  func testSubscriptionReconnectsAfterConnectionLoss() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: temperatureResponses(values: [21, 23])
    )
    try await session.install(fixture.credentials())
    let firstConnection = TemperatureSubscriptionConnection(
      messages: [
        .success(#"{"type":"auth_required"}"#),
        .success(#"{"type":"auth_ok"}"#),
        .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
        .failure(URLError(.networkConnectionLost)),
      ]
    )
    let secondConnection = TemperatureSubscriptionConnection(
      messages: [
        .success(#"{"type":"auth_required"}"#),
        .success(#"{"type":"auth_ok"}"#),
        .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
      ]
    )
    let sleeper = RecordingSubscriptionSleeper(blocks: true)
    let client = makeClient(
      session: session,
      connections: [firstConnection, secondConnection],
      retryDelays: [.seconds(3)],
      sleep: sleeper.sleep
    )
    var updates = client.temperatureUpdates().makeAsyncIterator()

    let initial = try snapshot(from: try await updates.next())
    let reconnecting = try await updates.next()
    XCTAssertEqual(reconnecting, .reconnecting(initial))
    await fulfillment(of: [sleeper.started], timeout: 1)
    sleeper.resume()
    let reconnected = try snapshot(from: try await updates.next())
    secondConnection.cancel()

    XCTAssertEqual(initial.map(\.value), [21])
    XCTAssertEqual(reconnected.map(\.value), [23])
    XCTAssertEqual(sleeper.delays, [.seconds(3)])
  }

  func testReconnectStatusPreservesBufferedInitialSnapshot() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: temperatureResponses(values: [21])
    )
    try await session.install(fixture.credentials())
    let connection = TemperatureSubscriptionConnection(
      messages: [
        .success(#"{"type":"auth_required"}"#),
        .success(#"{"type":"auth_ok"}"#),
        .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
      ]
    )
    let sleeper = RecordingSubscriptionSleeper(blocks: true)
    let client = makeClient(
      session: session,
      connections: [connection],
      retryDelays: [.seconds(3)],
      sleep: sleeper.sleep
    )
    let stream = client.temperatureUpdates()
    await fulfillment(of: [connection.blockedReceiveStarted], timeout: 1)

    connection.fail(with: URLError(.networkConnectionLost))
    await fulfillment(of: [sleeper.started], timeout: 1)
    var updates = stream.makeAsyncIterator()
    let reconnecting = try await updates.next()
    sleeper.cancel()

    let expected = HomeAssistantTemperatureReading(
      id: "climate.bedroom",
      name: "Bedroom",
      value: 21,
      unit: "°C",
      updatedAt: try Date.ISO8601FormatStyle().parse("2026-07-27T01:02:03Z")
    )
    XCTAssertEqual(reconnecting, .reconnecting([expected]))
  }

  func testSubscriptionFailsOverToNextHomeAssistantRoute() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: temperatureResponses(values: [21])
    )
    try await session.install(fixture.credentials())
    let connector = TemperatureSubscriptionConnector(
      connections: [
        TemperatureSubscriptionConnection(
          messages: [.failure(URLError(.cannotConnectToHost))]
        ),
        TemperatureSubscriptionConnection(
          messages: [
            .success(#"{"type":"auth_required"}"#),
            .success(#"{"type":"auth_ok"}"#),
            .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
          ]
        ),
      ]
    )
    let client = HomeAssistantTemperatureStream(
      session: session,
      apiClient: HomeAssistantAPIClient(
        session: session,
        climateIconLoader: TemperatureSubscriptionIconLoader(icons: [:])
      ),
      connector: connector,
      retryDelays: [.zero],
      sleep: { _ in }
    )
    var updates = client.temperatureUpdates().makeAsyncIterator()

    _ = try await updates.next()
    let live = try snapshot(from: try await updates.next())
    let currentCredentials = await session.currentCredentials()

    XCTAssertEqual(live.map(\.value), [21])
    XCTAssertEqual(
      connector.connectedURLs.map(\.absoluteString),
      [
        "ws://home.local:8123/api/websocket",
        "wss://home.example/api/websocket",
      ]
    )
    XCTAssertEqual(currentCredentials?.lastSuccessfulURL, fixture.externalURL)
  }
}

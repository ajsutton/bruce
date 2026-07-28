import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantTemperatureReconnectTests: XCTestCase {}

extension HomeAssistantTemperatureReconnectTests {
  func testReconnectBeforeInitialSnapshotIsPublished() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: temperatureResponses(values: [23]))
    try await session.install(fixture.credentials())
    let firstConnection = TemperatureSubscriptionConnection(
      messages: [.failure(URLError(.networkConnectionLost))]
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
    let probe = AsyncThrowingStreamTestProbe(client.temperatureUpdates())

    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let reconnecting = try probe.value(at: 0)
    await fulfillment(of: [sleeper.started], timeout: 1)
    sleeper.resume()
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let connected = try snapshot(from: probe.value(at: 1))
    secondConnection.cancel()

    XCTAssertEqual(reconnecting, .reconnecting([]))
    XCTAssertEqual(connected.map(\.value), [23])
  }

  func testOlderQueuedRemovalDoesNotDeleteNewerRestState() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: temperatureResponses(values: [23]))
    try await session.install(fixture.credentials())
    let connection = TemperatureSubscriptionConnection(
      messages: [
        .success(#"{"type":"auth_required"}"#),
        .success(#"{"type":"auth_ok"}"#),
        .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
        .success(
          stateRemovedEvent(
            entityID: "climate.bedroom",
            oldLastUpdated: "2026-07-27T01:01:00Z"
          )
        ),
      ]
    )
    let client = makeClient(session: session, connections: [connection])
    let probe = AsyncThrowingStreamTestProbe(client.temperatureUpdates())
    await fulfillment(of: [connection.blockedReceiveStarted], timeout: 1)

    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let afterOlderRemoval = try snapshot(from: probe.value(at: 0))
    connection.cancel()

    XCTAssertEqual(afterOlderRemoval.map(\.value), [23])
  }

  func testSubscriptionReconnectsAfterConnectionLoss() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: temperatureResponses(
        values: [21, 23],
        units: ["°C", "°F"]
      )
    )
    try await session.install(fixture.credentials())
    let firstConnection = TemperatureSubscriptionConnection(
      messages: [
        .success(#"{"type":"auth_required"}"#),
        .success(#"{"type":"auth_ok"}"#),
        .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
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
    let probe = AsyncThrowingStreamTestProbe(client.temperatureUpdates())

    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let initial = try snapshot(from: probe.value(at: 0))
    await fulfillment(of: [firstConnection.blockedReceiveStarted], timeout: 1)
    firstConnection.fail(with: URLError(.networkConnectionLost))
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let reconnecting = try probe.value(at: 1)
    XCTAssertEqual(reconnecting, .reconnecting(initial))
    await fulfillment(of: [sleeper.started], timeout: 1)
    sleeper.resume()
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)
    let reconnected = try snapshot(from: probe.value(at: 2))
    secondConnection.cancel()

    XCTAssertEqual(initial.map(\.value), [21])
    XCTAssertEqual(initial.map(\.unit), ["°C"])
    XCTAssertEqual(reconnected.map(\.value), [23])
    XCTAssertEqual(reconnected.map(\.unit), ["°F"])
    XCTAssertEqual(sleeper.delays, [.seconds(3)])
  }

  func testOlderRestSnapshotCannotRollBackNewerLiveStateOnReconnect() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(temperatureStates(value: 21), statusCode: 200),
        .success(temperatureStates(value: 20), statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())
    let firstConnection = authenticatedConnection()
    let secondConnection = authenticatedConnection()
    let sleeper = RecordingSubscriptionSleeper(blocks: true)
    let stream = HomeAssistantStateStream(
      session: session,
      connector: TemperatureSubscriptionConnector(
        connections: [firstConnection, secondConnection]
      ),
      retryDelays: [.zero],
      sleep: sleeper.sleep
    )
    let probe = AsyncThrowingStreamTestProbe(await stream.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    await fulfillment(of: [firstConnection.blockedReceiveStarted], timeout: 1)

    firstConnection.succeed(
      with: stateChangedEvent(entityID: "climate.bedroom", value: 25)
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    firstConnection.fail(with: URLError(.networkConnectionLost))
    await fulfillment(of: [sleeper.started], timeout: 1)
    sleeper.resume()
    await fulfillment(of: [probe.received(at: 3)], timeout: 1)

    let reconnected = try probe.value(at: 3)
    let reading = try XCTUnwrap(
      reconnected.states.first?.temperatureReading(unit: "°C", metadata: nil)
    )
    XCTAssertEqual(reconnected.phase, .live)
    XCTAssertEqual(reading.value, 25)
    XCTAssertEqual(
      fixture.apiLoader.requests.map(\.cachePolicy),
      [.reloadIgnoringLocalCacheData, .reloadIgnoringLocalCacheData]
    )
    secondConnection.cancel()
  }

  func testOlderRestSnapshotCannotResurrectRemovedStateOnReconnect() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(temperatureStates(value: 21), statusCode: 200),
        .success(temperatureStates(value: 20), statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())
    let firstConnection = authenticatedConnection()
    let secondConnection = authenticatedConnection()
    let sleeper = RecordingSubscriptionSleeper(blocks: true)
    let stream = HomeAssistantStateStream(
      session: session,
      connector: TemperatureSubscriptionConnector(
        connections: [firstConnection, secondConnection]
      ),
      retryDelays: [.zero],
      sleep: sleeper.sleep
    )
    let probe = AsyncThrowingStreamTestProbe(await stream.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    await fulfillment(of: [firstConnection.blockedReceiveStarted], timeout: 1)

    firstConnection.succeed(
      with: stateRemovedEvent(
        entityID: "climate.bedroom",
        oldLastUpdated: "2026-07-27T01:03:04Z"
      )
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    XCTAssertTrue(try probe.value(at: 1).states.isEmpty)

    firstConnection.fail(with: URLError(.networkConnectionLost))
    await fulfillment(of: [sleeper.started], timeout: 1)
    sleeper.resume()
    await fulfillment(of: [probe.received(at: 3)], timeout: 1)

    XCTAssertTrue(try probe.value(at: 3).states.isEmpty)
    secondConnection.cancel()
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
    let probe = AsyncThrowingStreamTestProbe(client.temperatureUpdates())
    await fulfillment(of: [connection.blockedReceiveStarted], timeout: 1)

    connection.fail(with: URLError(.networkConnectionLost))
    await fulfillment(of: [sleeper.started], timeout: 1)
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let reconnecting = try probe.value(at: 1)
    sleeper.cancel()

    let expected = HomeAssistantTemperatureReading(
      id: "climate.bedroom",
      name: "Bedroom",
      value: 21,
      targetValue: 22,
      unit: "°C",
      powerState: .poweredOn,
      operatingMode: .cooling
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
        climateMetadataLoader: TemperatureSubscriptionMetadataLoader(metadata: [:])
      ),
      connector: connector,
      retryDelays: [.zero],
      sleep: { _ in }
    )
    let probe = AsyncThrowingStreamTestProbe(client.temperatureUpdates())

    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let reconnecting = try probe.value(at: 0)
    let live = try snapshot(from: probe.value(at: 1))
    let currentCredentials = await session.currentCredentials()

    XCTAssertEqual(reconnecting, .reconnecting([]))
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

  func testSecondDisconnectionFailsBackToTheOtherRoute() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: temperatureResponses(values: [21, 22])
    )
    try await session.install(fixture.credentials())
    let firstLiveConnection = authenticatedConnection()
    let secondLiveConnection = authenticatedConnection()
    let connector = TemperatureSubscriptionConnector(
      connections: [
        TemperatureSubscriptionConnection(
          messages: [.failure(URLError(.cannotConnectToHost))]
        ),
        firstLiveConnection,
        secondLiveConnection,
      ]
    )
    let client = HomeAssistantTemperatureStream(
      session: session,
      apiClient: HomeAssistantAPIClient(
        session: session,
        climateMetadataLoader: TemperatureSubscriptionMetadataLoader(metadata: [:])
      ),
      connector: connector,
      retryDelays: [.zero],
      sleep: { _ in }
    )
    let probe = AsyncThrowingStreamTestProbe(client.temperatureUpdates())

    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let initialReconnect = try probe.value(at: 0)
    let firstLive = try snapshot(from: probe.value(at: 1))
    await fulfillment(of: [firstLiveConnection.blockedReceiveStarted], timeout: 1)
    firstLiveConnection.fail(with: URLError(.networkConnectionLost))
    await fulfillment(of: [probe.received(at: 3)], timeout: 1)
    let reconnecting = try probe.value(at: 2)
    let secondLive = try snapshot(from: probe.value(at: 3))
    secondLiveConnection.cancel()

    XCTAssertEqual(initialReconnect, .reconnecting([]))
    XCTAssertEqual(firstLive.map(\.value), [21])
    XCTAssertEqual(reconnecting, .reconnecting(firstLive))
    XCTAssertEqual(secondLive.map(\.value), [22])
    XCTAssertEqual(
      connector.connectedURLs.map(\.absoluteString),
      [
        "ws://home.local:8123/api/websocket",
        "wss://home.example/api/websocket",
        "ws://home.local:8123/api/websocket",
      ]
    )
  }
}

private func authenticatedConnection(
  endingWith error: (any Error)? = nil
) -> TemperatureSubscriptionConnection {
  var messages: [TemperatureSubscriptionConnection.Message] = [
    .success(#"{"type":"auth_required"}"#),
    .success(#"{"type":"auth_ok"}"#),
    .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
  ]
  if let error {
    messages.append(.failure(error))
  }
  return TemperatureSubscriptionConnection(messages: messages)
}

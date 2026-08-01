import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantTemperatureStreamTests: XCTestCase {
  func testSubscriptionPublishesInitialAndLiveTemperatureSnapshots() async throws {
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
    let client = makeClient(
      session: session,
      connections: [connection],
      icons: ["climate.bedroom": "mdi:bed"],
      kinds: ["climate.bedroom": .airConditioner]
    )
    let probe = AsyncThrowingStreamTestProbe(client.temperatureUpdates())

    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let initial = try snapshot(from: probe.value(at: 0))
    connection.succeed(
      with: stateChangedEvent(
        entityID: "climate.bedroom",
        value: 24,
        state: "auto",
        target: 22
      )
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let live = try snapshot(from: probe.value(at: 1))
    connection.cancel()
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    XCTAssertEqual(initial.map(\.value), [21])
    XCTAssertEqual(initial.map(\.targetValue), [22])
    XCTAssertEqual(initial.map(\.powerState), [.poweredOn])
    XCTAssertEqual(initial.map(\.kind), [.airConditioner])
    XCTAssertEqual(initial.map(\.operatingMode), [.cooling])
    XCTAssertEqual(live.map(\.value), [24])
    XCTAssertEqual(live.map(\.targetValue), [22])
    XCTAssertEqual(live.map(\.powerState), [.poweredOn])
    XCTAssertEqual(live.map(\.kind), [.airConditioner])
    XCTAssertEqual(live.map(\.operatingMode), [.automatic])
    XCTAssertEqual(live.first?.icon, "mdi:bed")
    XCTAssertThrowsError(try probe.value(at: 2))
    assertEventSubscriptions(connection)
  }

  func testSubscriptionRemovesClimateEntityWithoutCurrentTemperature() async throws {
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
    let client = makeClient(session: session, connections: [connection])
    let probe = AsyncThrowingStreamTestProbe(client.temperatureUpdates())

    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    connection.succeed(
      with: stateChangedEvent(entityID: "climate.bedroom", value: nil)
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let live = try snapshot(from: probe.value(at: 1))
    connection.cancel()

    XCTAssertTrue(live.isEmpty)
  }

  func testCancellingSubscriptionClosesBlockedWebSocket() async throws {
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
    let client = makeClient(session: session, connections: [connection])
    let consume = Task {
      for try await _ in client.temperatureUpdates() {}
    }
    await fulfillment(of: [connection.blockedReceiveStarted], timeout: 1)

    consume.cancel()
    try await consume.value

    XCTAssertTrue(connection.isCancelled)
  }

  func testSubscriptionBuffersOnlyNewestTemperatureSnapshot() async throws {
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
        .success(stateChangedEvent(entityID: "climate.bedroom", value: 22)),
        .success(stateChangedEvent(entityID: "climate.bedroom", value: 23)),
      ]
    )
    let client = makeClient(session: session, connections: [connection])
    let stream = client.temperatureUpdates()
    await fulfillment(of: [connection.blockedReceiveStarted], timeout: 1)
    let probe = AsyncThrowingStreamTestProbe(stream)

    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let newest = try snapshot(from: probe.value(at: 0))
    connection.cancel()

    XCTAssertEqual(newest.map(\.value), [23])
  }

  func testRejectedAuthenticationFinishesWithUnauthorizedError() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connection = TemperatureSubscriptionConnection(
      messages: [
        .success(#"{"type":"auth_required"}"#),
        .success(#"{"type":"auth_invalid"}"#),
      ]
    )
    let client = makeClient(session: session, connections: [connection])
    let probe = AsyncThrowingStreamTestProbe(client.temperatureUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    do {
      _ = try probe.value(at: 0)
      XCTFail("Expected WebSocket authentication to be rejected.")
    } catch HomeAssistantAPIError.unauthorized {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(connection.isCancelled)
  }

  func testRegistryUpdateReloadsClimatePresetLabels() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(temperatureStates(value: 21), statusCode: 200),
        .success(Data(#"{"unit_system":{"temperature":"°C"}}"#.utf8), statusCode: 200),
        .success(Data(#"{"unit_system":{"temperature":"°C"}}"#.utf8), statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())
    let connection = TemperatureSubscriptionConnection(
      messages: [
        .success(#"{"type":"auth_required"}"#),
        .success(#"{"type":"auth_ok"}"#),
        .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
      ]
    )
    let metadataLoader = UpdatingTemperatureMetadataLoader()
    let apiClient = HomeAssistantAPIClient(
      session: session,
      climateMetadataLoader: metadataLoader
    )
    let stream = HomeAssistantTemperatureStream(
      session: session,
      apiClient: apiClient,
      connector: TemperatureSubscriptionConnector(connections: [connection]),
      retryDelays: []
    )
    let probe = AsyncThrowingStreamTestProbe(stream.temperatureUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    connection.succeed(with: registryUpdatedEvent(type: "label_registry_updated"))
    await fulfillment(of: [metadataLoader.reloaded], timeout: 1)
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    connection.cancel()

    let refreshed = try snapshot(from: probe.value(at: 1))
    XCTAssertEqual(refreshed.first?.presetLabels.map(\.name), ["Bedrooms"])
  }

}

private final class UpdatingTemperatureMetadataLoader:
  HomeAssistantClimateMetadataLoading, @unchecked Sendable
{
  let reloaded = XCTestExpectation(description: "Climate metadata reloaded")

  private let lock = NSLock()
  private var loadCount = 0

  func loadClimateMetadata() async throws -> [String: HomeAssistantClimateMetadata] {
    let count = lock.withLock {
      loadCount += 1
      return loadCount
    }
    guard count > 1 else { return [:] }
    reloaded.fulfill()
    return [
      "climate.bedroom": HomeAssistantClimateMetadata(
        icon: nil,
        kind: .zone,
        presetLabels: [.init(id: "bedrooms", name: "Bedrooms")]
      )
    ]
  }
}

private func registryUpdatedEvent(type: String) -> String {
  let id = type == "label_registry_updated" ? 6 : 1
  return #"{"id":\#(id),"type":"event","event":{"event_type":"\#(type)","data":{}}}"#
}

private func assertEventSubscriptions(
  _ connection: TemperatureSubscriptionConnection,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(
    connection.sentMessageTypes,
    ["auth"] + Array(repeating: "subscribe_events", count: 6),
    file: file,
    line: line
  )
  XCTAssertEqual(
    connection.sentMessageJSON.compactMap { $0["event_type"] as? String },
    [
      "state_changed",
      "entity_registry_updated",
      "device_registry_updated",
      "area_registry_updated",
      "floor_registry_updated",
      "label_registry_updated",
    ],
    file: file,
    line: line
  )
}

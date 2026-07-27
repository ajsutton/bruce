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
        .success(
          stateChangedEvent(
            entityID: "climate.bedroom",
            value: 24,
            state: "off",
            target: 22
          )
        ),
      ]
    )
    let client = makeClient(
      session: session,
      connections: [connection],
      icons: ["climate.bedroom": "mdi:bed"]
    )
    var updates = client.temperatureUpdates().makeAsyncIterator()

    let initial = try snapshot(from: try await updates.next())
    let live = try snapshot(from: try await updates.next())
    connection.cancel()
    let finished = try await updates.next()

    XCTAssertEqual(initial.map(\.value), [21])
    XCTAssertEqual(initial.map(\.targetValue), [22])
    XCTAssertEqual(initial.map(\.powerState), [.poweredOn])
    XCTAssertEqual(live.map(\.value), [24])
    XCTAssertEqual(live.map(\.targetValue), [22])
    XCTAssertEqual(live.map(\.powerState), [.off])
    XCTAssertEqual(live.first?.icon, "mdi:bed")
    XCTAssertNil(finished)
    XCTAssertEqual(connection.sentMessageTypes, ["auth", "subscribe_events"])
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
        .success(stateChangedEvent(entityID: "climate.bedroom", value: nil)),
      ]
    )
    let client = makeClient(session: session, connections: [connection])
    var updates = client.temperatureUpdates().makeAsyncIterator()

    _ = try await updates.next()
    let live = try snapshot(from: try await updates.next())
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
    var updates = stream.makeAsyncIterator()

    let newest = try snapshot(from: try await updates.next())
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
    var updates = client.temperatureUpdates().makeAsyncIterator()

    do {
      _ = try await updates.next()
      XCTFail("Expected WebSocket authentication to be rejected.")
    } catch HomeAssistantAPIError.unauthorized {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(connection.isCancelled)
  }

}

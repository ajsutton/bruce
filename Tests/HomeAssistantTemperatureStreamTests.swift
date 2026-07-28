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

}

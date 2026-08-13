import XCTest

@testable import Bruce

final class ConnectionEventBufferTests: XCTestCase {
  func testPreSnapshotStateAndRegistryEventsForSameEntityRemainDistinctInEitherOrder() async throws
  {
    for stateFirst in [true, false] {
      let attempt = makeAttempt()
      let state = Data(stateChangedEvent(entityID: "climate.bedroom", value: 21).utf8)
      let registry = registryEvent(entityID: "climate.bedroom")

      if stateFirst {
        try await attempt.receive(state)
        try await attempt.receive(registry)
      } else {
        try await attempt.receive(registry)
        try await attempt.receive(state)
      }

      let publishing = try await attempt.beginPublishingEvents()
      XCTAssertEqual(Set(publishing.buffered), Set([state, registry]))
      await attempt.finish()
    }
  }

  func testPostSnapshotStateAndRegistryEventsForSameEntityRemainDistinctInEitherOrder() async throws
  {
    for stateFirst in [true, false] {
      let attempt = makeAttempt()
      let publishing = try await attempt.beginPublishingEvents()
      let state = Data(stateChangedEvent(entityID: "climate.bedroom", value: 21).utf8)
      let registry = registryEvent(entityID: "climate.bedroom")

      if stateFirst {
        try await attempt.receive(state)
        try await attempt.receive(registry)
      } else {
        try await attempt.receive(registry)
        try await attempt.receive(state)
      }

      var iterator = publishing.stream.makeAsyncIterator()
      let firstValue = try await iterator.next()
      let secondValue = try await iterator.next()
      let first = try XCTUnwrap(firstValue)
      let second = try XCTUnwrap(secondValue)
      XCTAssertEqual([first, second], stateFirst ? [state, registry] : [registry, state])
      await attempt.finish()
    }
  }

  func testPostSnapshotEventsCoalesceLatestRemovalByEntity() async throws {
    let attempt = HomeAssistantConnectionAttempt(
      id: UUID(), authenticationSessionEpoch: 1, routeCategory: "preferred", now: { 0 }
    )
    let events = try await attempt.beginPublishingEvents()
    for value in 1...100 {
      try await attempt.receive(
        Data(stateChangedEvent(entityID: "climate.bedroom", value: Double(value)).utf8)
      )
    }
    try await attempt.receive(
      Data(
        stateRemovedEvent(
          entityID: "climate.bedroom",
          oldLastUpdated: "2026-07-27T01:03:04Z"
        ).utf8
      )
    )
    try await attempt.receive(
      Data(stateChangedEvent(entityID: "climate.kitchen", value: 25).utf8)
    )

    var iterator = events.stream.makeAsyncIterator()
    let nextBedroom = try await iterator.next()
    let nextKitchen = try await iterator.next()
    let bedroom = try XCTUnwrap(nextBedroom)
    let kitchen = try XCTUnwrap(nextKitchen)
    await attempt.finish()
    let end = try await iterator.next()

    XCTAssertTrue(
      try XCTUnwrap(String(data: bedroom, encoding: .utf8)).contains(#""new_state": null"#))
    XCTAssertTrue(try XCTUnwrap(String(data: kitchen, encoding: .utf8)).contains("climate.kitchen"))
    XCTAssertNil(end)
  }

  func testBlockedDerivedStreamPreservesControlBeforeNewestLiveUpdate() async throws {
    var continuation: HomeAssistantTemperatureUpdateStream.Continuation?
    let updates = HomeAssistantTemperatureUpdateStream { continuation = $0 }
    let streamContinuation = try XCTUnwrap(continuation)
    let stale = temperatureReading(value: 21)
    let latest = temperatureReading(value: 23)
    streamContinuation.yield(.reconnecting([stale]))
    streamContinuation.yield(.live([latest]))
    streamContinuation.finish()

    var iterator = updates.makeAsyncIterator()
    let control = try await iterator.next()
    let live = try await iterator.next()
    let end = try await iterator.next()
    XCTAssertEqual(control, .reconnecting([latest]))
    XCTAssertEqual(live, .live([latest]))
    XCTAssertNil(end)
  }

  private func temperatureReading(value: Double) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: "climate.bedroom",
      name: "Bedroom",
      value: value,
      targetValue: nil,
      unit: "°C",
      powerState: .poweredOn
    )
  }

  private func makeAttempt() -> HomeAssistantConnectionAttempt {
    HomeAssistantConnectionAttempt(
      id: UUID(), authenticationSessionEpoch: 1, routeCategory: "preferred", now: { 0 }
    )
  }

  private func registryEvent(entityID: String) -> Data {
    Data(
      #"{"id":2,"type":"event","event":{"event_type":"entity_registry_updated","data":{"entity_id":"\#(entityID)"}}}"#
        .utf8
    )
  }
}

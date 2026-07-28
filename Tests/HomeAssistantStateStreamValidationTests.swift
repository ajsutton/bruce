import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantStateStreamValidationTests: XCTestCase {
  func testInitialSnapshotRejectsMissingOrderingTimestamp() async throws {
    let states = Data(
      #"[{"entity_id":"climate.bedroom","state":"cool","attributes":{}}]"#.utf8
    )
    try await assertInitialSnapshotRejected(states)
  }

  func testInitialSnapshotRejectsDuplicateEntityIDs() async throws {
    let states = Data(
      #"""
      [
        {
          "entity_id":"climate.bedroom",
          "state":"cool",
          "attributes":{},
          "last_updated":"2026-07-27T01:02:03Z"
        },
        {
          "entity_id":"climate.bedroom",
          "state":"heat",
          "attributes":{},
          "last_updated":"2026-07-27T01:03:04Z"
        }
      ]
      """#.utf8
    )
    try await assertInitialSnapshotRejected(states)
  }

  func testLiveEventRejectsMismatchedEntityID() async throws {
    try await assertLiveEventRejected(mismatchedStateChangedEvent())
  }

  func testLiveEventRejectsOmittedNewState() async throws {
    try await assertLiveEventRejected(stateChangedEventOmittingNewState())
  }

  private func assertInitialSnapshotRejected(_ states: Data) async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(states, statusCode: 200)]
    )
    try await session.install(fixture.credentials())
    let stream = HomeAssistantStateStream(
      session: session,
      connector: TemperatureSubscriptionConnector(
        connections: [validationAuthenticatedConnection()]
      ),
      retryDelays: []
    )
    let probe = AsyncThrowingStreamTestProbe(await stream.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    do {
      _ = try probe.value(at: 0)
      XCTFail("Expected the invalid initial state snapshot to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Unexpected initial-state validation error: \(error)")
    }
  }

  private func assertLiveEventRejected(_ event: String) async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [.success(temperatureStates(value: 21), statusCode: 200)]
    )
    try await session.install(fixture.credentials())
    let connection = validationAuthenticatedConnection(event: event)
    let stream = HomeAssistantStateStream(
      session: session,
      connector: TemperatureSubscriptionConnector(connections: [connection]),
      retryDelays: []
    )
    let probe = AsyncThrowingStreamTestProbe(await stream.stateUpdates())
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)

    _ = try probe.value(at: 0)
    do {
      _ = try probe.value(at: 1)
      XCTFail("Expected the invalid live event to be rejected.")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Unexpected live-event validation error: \(error)")
    }
  }
}

private func validationAuthenticatedConnection(
  event: String? = nil
) -> TemperatureSubscriptionConnection {
  var messages: [TemperatureSubscriptionConnection.Message] = [
    .success(#"{"type":"auth_required"}"#),
    .success(#"{"type":"auth_ok"}"#),
    .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
  ]
  if let event {
    messages.append(.success(event))
  }
  return TemperatureSubscriptionConnection(messages: messages)
}

private func mismatchedStateChangedEvent() -> String {
  #"""
  {
    "id": 1,
    "type": "event",
    "event": {
      "event_type": "state_changed",
      "data": {
        "entity_id": "climate.bedroom",
        "new_state": {
          "entity_id": "climate.office",
          "state": "cool",
          "attributes": {},
          "last_updated": "2026-07-27T01:03:04Z"
        },
        "old_state": null
      }
    }
  }
  """#
}

private func stateChangedEventOmittingNewState() -> String {
  #"""
  {
    "id": 1,
    "type": "event",
    "event": {
      "event_type": "state_changed",
      "data": {
        "entity_id": "climate.bedroom",
        "old_state": {
          "entity_id": "climate.bedroom",
          "state": "cool",
          "attributes": {},
          "last_updated": "2026-07-27T01:03:04Z"
        }
      }
    }
  }
  """#
}

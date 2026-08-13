import Foundation
import XCTest

@testable import Bruce

final class ConnectionSupervisorCommandTests: XCTestCase {
  func testConcurrentCommandsReceiveReorderedResponsesByID() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection(blocksCommands: true)
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection])
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let firstSent = connection.commandSent(at: 0)
    let secondSent = connection.commandSent(at: 1)
    let command = command

    let first = Task { try await supervisor.perform(command) }
    await fulfillment(of: [firstSent], timeout: 1)
    let second = Task { try await supervisor.perform(command) }
    await fulfillment(of: [secondSent], timeout: 1)
    let ids = connection.commandIDs
    connection.completeCommand(id: ids[1], result: #"{"marker":"second"}"#)
    let secondResponse = try await second.value
    connection.completeCommand(id: ids[0], result: #"{"marker":"first"}"#)
    let firstResponse = try await first.value

    XCTAssertEqual(try responseID(secondResponse), ids[1])
    XCTAssertEqual(try responseID(firstResponse), ids[0])
    await probe.cancel()
  }

  func testCancelledCommandIgnoresLateResponse() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection(blocksCommands: true)
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection])
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let firstSent = connection.commandSent(at: 0)
    let command = command
    let cancelled = Task { try await supervisor.perform(command) }
    await fulfillment(of: [firstSent], timeout: 1)
    let cancelledID = try XCTUnwrap(connection.commandIDs.first)

    cancelled.cancel()
    do {
      _ = try await cancelled.value
      XCTFail("Expected the command to be cancelled.")
    } catch is CancellationError {
    }
    connection.completeCommand(id: cancelledID, result: #"{"marker":"late"}"#)

    let nextSent = connection.commandSent(at: 1)
    let next = Task { try await supervisor.perform(command) }
    await fulfillment(of: [nextSent], timeout: 1)
    let nextID = connection.commandIDs[1]
    connection.completeCommand(id: nextID, result: #"{"marker":"current"}"#)
    let response = try await next.value

    XCTAssertEqual(try responseID(response), nextID)
    XCTAssertFalse(connection.isCancelled)
    await probe.cancel()
  }

  func testCommandSendFailureInvalidatesAttemptAndRecovers() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection(
      commandSendError: URLError(.networkConnectionLost)
    )
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let commandSent = first.commandSent(at: 0)

    do {
      _ = try await supervisor.perform(command)
      XCTFail("Expected the command send to fail.")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .networkConnectionLost)
    }
    await fulfillment(of: [commandSent, first.cancelled, probe.received(at: 2)], timeout: 1)

    XCTAssertEqual(try probe.value(at: 1).phase, .reconnecting)
    XCTAssertEqual(try probe.value(at: 2).phase, .live)
    XCTAssertEqual(connector.connectionCount, 2)
    await probe.cancel()
  }

  func testCommandTimeoutReplacesAttempt() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection(blocksCommands: true)
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let clock = ControlledConnectionClock()
    let supervisor = fixture.makeSupervisor(
      connector: connector,
      clock: clock.connectionClock
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let commandSent = first.commandSent(at: 0)
    let deadline = clock.expectSleep(.seconds(30))
    let command = command
    let request = Task { try await supervisor.perform(command) }
    await fulfillment(of: [commandSent, deadline], timeout: 1)

    clock.resume(.seconds(30), advancingBy: 30)
    do {
      _ = try await request.value
      XCTFail("Expected the command deadline to expire.")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .timedOut)
    }
    await fulfillment(of: [first.cancelled, probe.received(at: 2)], timeout: 1)

    XCTAssertEqual(try probe.value(at: 1).phase, .reconnecting)
    XCTAssertEqual(try probe.value(at: 2).phase, .live)
    XCTAssertEqual(connector.connectionCount, 2)
    await probe.cancel()
  }

  func testStopWhileCommandIsBlockedCannotRestartConnection() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection(blocksCommands: true)
    let connector = ScriptedHomeAssistantConnector(connections: [connection])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let sent = connection.commandSent(at: 0)
    let command = command
    let request = Task { try await supervisor.perform(command) }
    await fulfillment(of: [sent], timeout: 1)

    await supervisor.stop()
    do {
      _ = try await request.value
      XCTFail("Expected stopped command to fail.")
    } catch {
      XCTAssertTrue(error is CancellationError || error is HomeAssistantAPIError)
    }

    XCTAssertTrue(connection.isCancelled)
    XCTAssertEqual(connector.connectionCount, 1)
    await probe.cancel()
  }

  func testCommandDuringReconnectJoinsReplacementAttempt() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection(
      blocksAuthentication: true,
      blocksCommands: true
    )
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    first.fail(with: URLError(.networkConnectionLost))
    await fulfillment(of: [replacement.authenticationStarted], timeout: 1)
    let commandSent = replacement.commandSent(at: 0)
    let command = command
    let request = Task { try await supervisor.perform(command) }
    replacement.completeAuthentication()
    await fulfillment(of: [commandSent], timeout: 1)
    let id = try XCTUnwrap(replacement.commandIDs.first)
    replacement.completeCommand(id: id)
    let response = try await request.value
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    XCTAssertEqual(try responseID(response), id)
    XCTAssertEqual(connector.connectionCount, 2)
    XCTAssertEqual(try probe.value(at: 2).phase, .live)
    await probe.cancel()
  }

  func testEOFDuringSnapshotCannotPublishFinishedAttemptLive() async throws {
    let snapshotLoader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let fixture = SupervisorFixture(snapshotValues: [], loader: snapshotLoader)
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [snapshotLoader.started], timeout: 1)

    first.fail(with: URLError(.networkConnectionLost))
    snapshotLoader.succeed(with: temperatureStates(value: 23), statusCode: 200)
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)

    XCTAssertEqual(try probe.value(at: 0).phase, .reconnecting)
    XCTAssertEqual(try probe.value(at: 1).phase, .live)
    XCTAssertEqual(connector.connectionCount, 2)
    XCTAssertTrue(first.isCancelled)
    await probe.cancel()
  }

  private var command: HomeAssistantWebSocketCommand {
    HomeAssistantWebSocketCommand(type: "test_command")
  }

  private func responseID(_ data: Data) throws -> Int {
    let object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    return try XCTUnwrap(object["id"] as? Int)
  }
}

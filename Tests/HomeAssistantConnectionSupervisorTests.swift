import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantConnectionSupervisorTests: XCTestCase {
  func testEOFReconnectsWithoutReplacingConsumer() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)

    first.fail(with: URLError(.networkConnectionLost))
    await fulfillment(of: [probe.received(at: 2)], timeout: 5)
    let initial = try probe.value(at: 0)
    let reconnecting = try probe.value(at: 1)
    let recovered = try probe.value(at: 2)
    await probe.cancel()

    XCTAssertEqual(reconnecting.phase, .reconnecting)
    XCTAssertEqual(temperature(from: reconnecting), 21)
    XCTAssertEqual(recovered.phase, .live)
    XCTAssertNotEqual(recovered.generation, initial.generation)
    XCTAssertEqual(temperature(from: recovered), 23)
    XCTAssertEqual(connector.connectionCount, 2)
    XCTAssertEqual(first.subscriptionCount, 6)
    XCTAssertEqual(replacement.subscriptionCount, 6)
  }

  func testEventDuringSnapshotCannotBeRolledBack() async throws {
    let snapshotLoader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let fixture = SupervisorFixture(snapshotValues: [], loader: snapshotLoader)
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection()
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection])
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [snapshotLoader.started], timeout: 5)

    connection.yield(stateChangedEvent(entityID: "climate.bedroom", value: 24))
    snapshotLoader.succeed(with: temperatureStates(value: 21), statusCode: 200)
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)
    let live = try probe.value(at: 0)
    await probe.cancel()

    XCTAssertEqual(live.phase, .live)
    XCTAssertEqual(temperature(from: live), 24)
  }

  func testSnapshotDeadlineReplacesAttemptWhileStaleLoadRemainsBlocked() async throws {
    let snapshotLoader = FirstSnapshotBlockingHomeAssistantLoader(replacementValue: 23)
    let fixture = SupervisorFixture(snapshotValues: [], loader: snapshotLoader)
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let clock = ControlledConnectionClock()
    let deadlineScheduled = clock.expectSleep(.seconds(30))
    var supervisor: HomeAssistantConnectionSupervisor? = fixture.makeSupervisor(
      connector: connector,
      clock: clock.connectionClock
    )
    var stateUpdates = await supervisor?.stateUpdates()
    var probe: AsyncThrowingStreamTestProbe<HomeAssistantStateUpdate>? =
      AsyncThrowingStreamTestProbe(try XCTUnwrap(stateUpdates))
    await fulfillment(
      of: [snapshotLoader.firstSnapshotStarted, deadlineScheduled],
      timeout: 5
    )

    clock.resume(.seconds(30), advancingBy: 30)
    await fulfillment(of: [try XCTUnwrap(probe).received(at: 1)], timeout: 5)
    await probe?.cancel()
    probe = nil

    XCTAssertTrue(first.isCancelled)
    XCTAssertEqual(connector.connectionCount, 2)
    XCTAssertEqual(snapshotLoader.requestCount, 2)
    XCTAssertFalse(snapshotLoader.hasReleasedFirstSnapshot)
    await supervisor?.stop()
    stateUpdates = nil
    supervisor = nil
    XCTAssertFalse(snapshotLoader.hasReleasedFirstSnapshot)
    snapshotLoader.releaseFirstSnapshot()
    await fulfillment(of: [snapshotLoader.firstSnapshotFinished], timeout: 5)
  }

  func testRegistryEventRotatesMetadataGenerationExactlyOnce() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection()
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection])
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)
    let initial = try probe.value(at: 0)

    connection.yield(
      #"{"id":2,"type":"event","event":{"event_type":"entity_registry_updated","data":{}}}"#
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 5)
    let registryUpdate = try probe.value(at: 1)
    await probe.cancel()

    XCTAssertEqual(registryUpdate.phase, .live)
    XCTAssertNotEqual(registryUpdate.generation, initial.generation)
  }

  func testStopRejectsStaleReadinessSnapshotBeforeConsumerRegistration() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    try await fixture.install()
    let snapshot = ControlledCredentialSnapshot()
    let connector = ScriptedHomeAssistantConnector(connections: [])
    let supervisor = HomeAssistantConnectionSupervisor(
      session: fixture.session,
      connector: connector,
      credentialEvents: fixture.credentialEvents,
      connectionSnapshot: snapshot.load
    )
    let readiness = Task { try await supervisor.requireFreshLiveData() }
    await fulfillment(of: [snapshot.started], timeout: 5)

    await supervisor.stop()
    snapshot.resume()
    do {
      try await readiness.value
      XCTFail("Expected stale readiness acquisition to be cancelled.")
    } catch is CancellationError {
    }

    XCTAssertEqual(connector.connectionCount, 0)
    let hasNoConsumers = await supervisor.continuations.isEmpty
    let hasNoReadinessWaiters = await supervisor.readinessWaiters.isEmpty
    XCTAssertTrue(hasNoConsumers)
    XCTAssertTrue(hasNoReadinessWaiters)
  }

  func testAuthenticationSessionReplacementCancelsOldSocketAndRejectsLateEvent() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)

    var credentials = fixture.credentials
    credentials.accessToken = "replacement-access"
    try await fixture.session.install(credentials)
    first.yield(stateChangedEvent(entityID: "climate.bedroom", value: 99))
    await fulfillment(of: [probe.received(at: 2)], timeout: 5)
    let invalidated = try probe.value(at: 1)
    let recovered = try probe.value(at: 2)
    await probe.cancel()

    XCTAssertTrue(first.isCancelled)
    XCTAssertEqual(invalidated.phase, .reconnecting)
    XCTAssertTrue(invalidated.states.isEmpty)
    XCTAssertEqual(connector.connectionCount, 2)
    XCTAssertEqual(temperature(from: recovered), 23)
  }

  func testSuspensionPreservesConsumerAndResumesOneConnection() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)

    await supervisor.setApplicationActive(false)
    await fulfillment(of: [probe.received(at: 1)], timeout: 5)
    let suspendedState = await supervisor.state
    await supervisor.setApplicationActive(true)
    await fulfillment(of: [probe.received(at: 2)], timeout: 5)
    let recovered = try probe.value(at: 2)
    await probe.cancel()

    XCTAssertEqual(suspendedState, .suspended)
    XCTAssertTrue(first.isCancelled)
    XCTAssertEqual(recovered.phase, .live)
    XCTAssertEqual(temperature(from: recovered), 23)
    XCTAssertEqual(connector.connectionCount, 2)
  }

  func testManualReadinessWaitsForReplacementLiveSnapshot() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection(blocksAuthentication: true)
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)
    let readiness = Task { try await supervisor.requireFreshLiveData() }
    await fulfillment(of: [replacement.authenticationStarted], timeout: 5)
    XCTAssertFalse(readiness.isCancelled)

    replacement.completeAuthentication()
    try await readiness.value
    await fulfillment(of: [probe.received(at: 2)], timeout: 5)
    let recovered = try probe.value(at: 2)
    await probe.cancel()

    XCTAssertEqual(recovered.phase, .live)
    XCTAssertEqual(temperature(from: recovered), 23)
    XCTAssertEqual(connector.connectionCount, 2)
  }

  func testFullJitterBackoffIncreasesAndCapsIndefinitely() {
    let policy = HomeAssistantConnectionRetryPolicy(
      initialWindow: 5,
      maximumWindow: 60,
      randomUnit: { 1 }
    )

    let delays = (1...8).map { policy.delay(afterFailure: $0) }

    XCTAssertEqual(
      delays,
      [.seconds(5), .seconds(10), .seconds(20), .seconds(40)]
        + Array(repeating: .seconds(60), count: 4)
    )
  }

}

extension HomeAssistantConnectionSupervisorTests {
  func testMissedApplicationHeartbeatUsesNormalRecovery() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection(respondsToPing: false)
    let replacement = ScriptedHomeAssistantConnection()
    let clock = ControlledConnectionClock()
    let heartbeatScheduled = clock.expectSleep(.seconds(60))
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(
      connector: connector,
      clock: clock.connectionClock
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0), heartbeatScheduled], timeout: 5)

    let deadlineScheduled = clock.expectSleep(.seconds(30))
    clock.resume(.seconds(60), advancingBy: 60)
    await fulfillment(of: [first.pingStarted, deadlineScheduled], timeout: 5)
    clock.resume(.seconds(30), advancingBy: 30)
    await fulfillment(of: [probe.received(at: 2)], timeout: 5)
    let recovered = try probe.value(at: 2)
    await probe.cancel()

    XCTAssertEqual(first.pingCount, 1)
    XCTAssertTrue(first.isCancelled)
    XCTAssertEqual(recovered.phase, .live)
    XCTAssertEqual(connector.connectionCount, 2)
  }

  func temperature(from update: HomeAssistantStateUpdate) -> Double? {
    update.states.first?.temperatureReading(unit: "°C", metadata: nil)?.value
  }

  func refreshedToken() -> Data {
    Data(
      """
      {
        "access_token": "refreshed-access",
        "token_type": "Bearer",
        "expires_in": 1800
      }
      """.utf8
    )
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
}

struct CleanWebSocketClose: Error {}

private final class FirstSnapshotBlockingHomeAssistantLoader:
  HomeAssistantHTTPDataLoading, @unchecked Sendable
{
  let firstSnapshotStarted = XCTestExpectation(description: "First snapshot started")
  let firstSnapshotFinished = XCTestExpectation(description: "First snapshot finished")

  private let lock = NSLock()
  private let replacementValue: Double
  private var firstContinuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
  private var storedRequestCount = 0
  private var storedHasReleasedFirstSnapshot = false

  init(replacementValue: Double) {
    self.replacementValue = replacementValue
  }

  var requestCount: Int { lock.withLock { storedRequestCount } }

  var hasReleasedFirstSnapshot: Bool {
    lock.withLock { storedHasReleasedFirstSnapshot }
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let requestIndex = lock.withLock {
      defer { storedRequestCount += 1 }
      return storedRequestCount
    }
    if requestIndex > 0 {
      return try response(for: request, value: replacementValue)
    }
    firstSnapshotStarted.fulfill()
    let response = try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        firstContinuation = continuation
      }
    }
    firstSnapshotFinished.fulfill()
    return response
  }

  func releaseFirstSnapshot() {
    let continuation = lock.withLock {
      storedHasReleasedFirstSnapshot = true
      defer { firstContinuation = nil }
      return firstContinuation
    }
    guard let continuation else { return }
    do {
      continuation.resume(returning: try response(for: nil, value: 21))
    } catch {
      continuation.resume(throwing: error)
    }
  }

  private func response(
    for request: URLRequest?,
    value: Double
  ) throws -> (Data, HTTPURLResponse) {
    guard
      let response = HTTPURLResponse(
        url: request?.url ?? URL(fileURLWithPath: "/"),
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return (temperatureStates(value: value), response)
  }
}

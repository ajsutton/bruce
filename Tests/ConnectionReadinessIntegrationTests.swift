import Combine
import XCTest

@testable import Bruce

@MainActor
final class ConnectionReadinessIntegrationTests: XCTestCase {
  func testActualTemperatureStoreMustBecomeLiveBeforeReadinessCompletes() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection()
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection])
    )
    let loader = ControlledTemperatureLoader(requestCount: 1, providesContinuousUpdates: true)
    let store = HomeAssistantTemperatureStore(loader: loader)
    let completion = ReadinessCompletionState()
    let readiness = Task {
      try await store.requireFreshLiveData(from: supervisor, deadline: .seconds(10))
      completion.complete()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 5)
    await fulfillment(of: [connection.authenticationStarted], timeout: 5)

    XCTAssertFalse(completion.isComplete)
    loader.yieldRequest(0, update: .live([]))
    try await readiness.value

    XCTAssertTrue(store.isLive)
    XCTAssertTrue(completion.isComplete)
    await store.synchronize(with: .signedOut)
    await supervisor.stop()
  }

  func testLiveStoreReadinessReusesExistingTemperatureObservation() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 22])
    try await fixture.install()
    let firstConnection = ScriptedHomeAssistantConnection()
    let secondConnection = ScriptedHomeAssistantConnection()
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(
        connections: [firstConnection, secondConnection]
      )
    )
    let loader = ControlledTemperatureLoader(
      requestCount: 1,
      providesContinuousUpdates: true
    )
    let store = HomeAssistantTemperatureStore(loader: loader)
    let load = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 5)
    loader.yieldRequest(0, update: .live([]))
    let firstReadiness = Task {
      try await store.requireFreshLiveData(from: supervisor, deadline: .seconds(10))
    }
    await fulfillment(of: [firstConnection.authenticationStarted], timeout: 5)
    loader.yieldRequest(0, update: .refreshing([]))
    loader.yieldRequest(0, update: .live([]))
    try await firstReadiness.value

    let secondReadiness = Task {
      try await store.requireFreshLiveData(from: supervisor, deadline: .seconds(10))
    }
    await fulfillment(of: [secondConnection.authenticationStarted], timeout: 5)
    loader.yieldRequest(0, update: .refreshing([]))
    loader.yieldRequest(0, update: .live([]))
    try await secondReadiness.value

    XCTAssertEqual(loader.requestCount, 1)
    loader.finishRequest(0)
    await load.value
    await supervisor.stop()
  }

  func testNonReadyAccessCancelsTemporaryTemperatureObservation() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection(blocksCommands: true)
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection])
    )
    let loader = ControlledTemperatureLoader(
      requestCount: 1,
      providesContinuousUpdates: true
    )
    let store = HomeAssistantTemperatureStore(loader: loader)
    let cancelled = loader.cancelled(at: 0)
    let readiness = Task {
      try await store.requireFreshLiveData(from: supervisor, deadline: .seconds(10))
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 5)
    await fulfillment(of: [connection.authenticationStarted], timeout: 5)

    await store.synchronize(with: .requiresUserAction)
    await fulfillment(of: [cancelled], timeout: 5)
    do {
      try await readiness.value
      XCTFail("Expected readiness cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    await supervisor.stop()
  }

  func testFailedManualReadinessLeavesSharedFeedRecovering() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let failed = ScriptedHomeAssistantConnection()
    failed.fail(with: URLError(.notConnectedToInternet))
    let recovered = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, failed, recovered])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)

    do {
      try await supervisor.requireFreshLiveData()
      XCTFail("Expected the failed replacement to fail manual readiness.")
    } catch {
      XCTAssertTrue(HomeAssistantRequestRouter.isConnectivityFailure(error))
    }
    await fulfillment(of: [recovered.authenticationStarted, probe.received(at: 3)], timeout: 5)

    XCTAssertEqual(try probe.value(at: 1).phase, .refreshing)
    XCTAssertEqual(try probe.value(at: 2).phase, .reconnecting)
    XCTAssertEqual(try probe.value(at: 3).phase, .live)
    XCTAssertEqual(connector.connectionCount, 3)
    await probe.cancel()
  }

  func testFailedReadinessDoesNotReplaceReconnectingStoreObservation() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let failed = ScriptedHomeAssistantConnection()
    failed.fail(with: URLError(.notConnectedToInternet))
    let recovered = ScriptedHomeAssistantConnection()
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [first, failed, recovered])
    )
    let feed = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [feed.received(at: 0)], timeout: 5)
    let loader = ControlledTemperatureLoader(requestCount: 1, providesContinuousUpdates: true)
    let store = HomeAssistantTemperatureStore(loader: loader)
    let observation = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 0)], timeout: 5)
    loader.yieldRequest(0, update: .live([]))
    loader.yieldRequest(0, update: .reconnecting([]))

    do {
      try await store.requireFreshLiveData(from: supervisor, deadline: .seconds(10))
      XCTFail("Expected the failed replacement to fail readiness.")
    } catch {
      XCTAssertTrue(HomeAssistantRequestRouter.isConnectivityFailure(error))
    }
    let becameLive = expectation(description: "Existing temperature observation recovered")
    let liveSubscription = store.$isLive
      .filter { $0 }
      .prefix(1)
      .sink { _ in becameLive.fulfill() }
    loader.yieldRequest(0, update: .live([]))
    await fulfillment(of: [becameLive], timeout: 5)

    XCTAssertTrue(store.isLive)
    XCTAssertEqual(loader.requestCount, 1)
    withExtendedLifetime(liveSubscription) {}
    loader.finishRequest(0)
    await observation.value
    await feed.cancel()
    await supervisor.stop()
  }
}

private final class ReadinessCompletionState: @unchecked Sendable {
  private let lock = NSLock()
  private var completed = false

  var isComplete: Bool { lock.withLock { completed } }

  func complete() {
    lock.withLock { completed = true }
  }
}

import XCTest

@testable import Bruce

@MainActor
final class TemperatureReadinessCancellationTests: XCTestCase {
  func testCancellingReadinessReturnsWithoutWaitingForTemperatureDeadline() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21])
    try await fixture.install()
    let connection = ScriptedHomeAssistantConnection(blocksAuthentication: true)
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(connections: [connection])
    )
    let loader = ControlledTemperatureLoader(requestCount: 1, providesContinuousUpdates: true)
    let deadline = AsyncStream<Void>.makeStream()
    let store = HomeAssistantTemperatureStore(
      loader: loader,
      sleep: { _ in
        for await _ in deadline.stream {}
        try Task.checkCancellation()
      }
    )
    let finished = expectation(description: "Readiness cancelled before deadline advanced")
    let readiness = Task {
      do {
        try await store.requireFreshLiveData(from: supervisor)
        XCTFail("Expected cancellation")
      } catch is CancellationError {
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
      finished.fulfill()
    }
    await fulfillment(of: [connection.authenticationStarted], timeout: 2)
    readiness.cancel()
    await fulfillment(of: [finished], timeout: 2)
    deadline.continuation.finish()
    await readiness.value
    await fulfillment(of: [loader.cancelled(at: 0)], timeout: 2)
    await supervisor.stop()
  }

  func testConnectionFailureReturnsWithoutWaitingForTemperatureDeadline() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let failed = ScriptedHomeAssistantConnection()
    failed.fail(with: URLError(.notConnectedToInternet))
    let supervisor = fixture.makeSupervisor(
      connector: ScriptedHomeAssistantConnector(
        connections: [ScriptedHomeAssistantConnection(), failed, ScriptedHomeAssistantConnection()]
      )
    )
    let feed = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [feed.received(at: 0)], timeout: 5)
    let loader = ControlledTemperatureLoader(requestCount: 1, providesContinuousUpdates: true)
    let deadline = AsyncStream<Void>.makeStream()
    let store = HomeAssistantTemperatureStore(
      loader: loader,
      sleep: { _ in
        for await _ in deadline.stream {}
        try Task.checkCancellation()
      }
    )
    let finished = expectation(description: "Readiness failed before deadline advanced")
    let readiness = Task {
      do {
        try await store.requireFreshLiveData(from: supervisor)
        XCTFail("Expected the connection failure")
      } catch {
        XCTAssertTrue(HomeAssistantRequestRouter.isConnectivityFailure(error))
      }
      finished.fulfill()
    }
    await fulfillment(of: [finished], timeout: 2)
    // Release even on failure so a regression cannot strand the test task.
    deadline.continuation.finish()
    await readiness.value
    await fulfillment(of: [loader.cancelled(at: 0)], timeout: 2)
    await feed.cancel()
    await supervisor.stop()
  }
}

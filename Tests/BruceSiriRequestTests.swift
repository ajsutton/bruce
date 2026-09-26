import XCTest

@testable import Bruce

@MainActor
final class BruceSiriRequestTests: XCTestCase {
  func testRepeatedDeadlinesReleaseWaitersWhileSharedRestoreRemainsSuspended() async throws {
    try await assertSharedRestoreCanOutliveRequests(cancel: false)
  }

  func testRepeatedCancellationsReleaseWaitersWhileSharedRestoreRemainsSuspended() async throws {
    try await assertSharedRestoreCanOutliveRequests(cancel: true)
  }

  private func assertSharedRestoreCanOutliveRequests(cancel: Bool) async throws {
    let connection = SuspendedSiriConnection()
    let store = HomeAssistantSetupStore(
      discovery: EmptyTemperatureDiscovery(), connection: connection)
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    let client = HomeAssistantAPIClient(session: session)
    for index in 0..<2 {
      let deadline = ControlledHomeEnergyDelay(delayCount: 1)
      let finished = expectation(description: "Siri request \(index) returned")
      let prepareFinished = expectation(description: "Preparation wrapper \(index) released")
      let prepareStarted = expectation(description: "Preparation wrapper \(index) entered")
      let service = BruceSiriService(
        energy: client,
        charger: client,
        prepare: {
          defer { prepareFinished.fulfill() }
          prepareStarted.fulfill()
          try await store.prepareSavedConnection()
        },
        waitForTimeout: { try await deadline.sleep(.seconds(12)) }
      )
      let query = Task {
        defer { finished.fulfill() }
        do {
          return Result<Double, any Error>.success(try await service.solarGeneration())
        } catch {
          return .failure(error)
        }
      }
      await fulfillment(of: [prepareStarted, deadline.started(at: 0)], timeout: 1)
      if index == 0 { await fulfillment(of: [connection.started], timeout: 1) }

      if cancel { query.cancel() } else { deadline.finish(0) }

      let completion = await XCTWaiter.fulfillment(of: [finished, prepareFinished], timeout: 1)
      XCTAssertEqual(completion, .completed)
      if completion != .completed { connection.finish() }
      assertResult(await query.value, cancelled: cancel)
    }
    XCTAssertEqual(connection.restoreCount, 1)
    XCTAssertTrue(fixture.apiLoader.requests.isEmpty)
    connection.finish()
  }

  private func assertResult(_ result: Result<Double, any Error>, cancelled: Bool) {
    switch result {
    case .failure(is CancellationError) where cancelled:
      break
    case .failure(BruceSiriError.connectionUnavailable) where !cancelled:
      break
    default:
      XCTFail("Unexpected request result: \(result)")
    }
  }
}

@MainActor
private final class SuspendedSiriConnection: HomeAssistantConnecting {
  let started = XCTestExpectation(description: "Shared restore started")
  private var continuation: CheckedContinuation<HomeAssistantCredentials?, Never>?
  private(set) var restoreCount = 0

  func restore() async throws -> HomeAssistantCredentials? {
    restoreCount += 1
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
      started.fulfill()
    }
  }

  func finish() {
    continuation?.resume(returning: nil)
    continuation = nil
  }

  func authenticate(to candidate: HomeAssistantConnectionCandidate) async throws
    -> HomeAssistantCredentials
  {
    throw HomeAssistantAPIError.noCredentials
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    throw HomeAssistantAPIError.noCredentials
  }

  func disconnect() async throws {}
  func cancel() {}
}

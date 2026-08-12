import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantStatePreflightRecoveryTests: XCTestCase {
  func testUnrecoverableSnapshotResponseIsTerminal() {
    let attempt = HomeAssistantReconnectAttempt.starting(
      hasPublishedSnapshot: true,
      latestStates: []
    )

    XCTAssertFalse(
      HomeAssistantStateStream.shouldReconnect(
        after: HomeAssistantAPIError.server(statusCode: 403),
        attempt: attempt
      )
    )
  }

  func testAvailabilitySnapshotResponseRemainsRetryable() {
    let attempt = HomeAssistantReconnectAttempt.starting(
      hasPublishedSnapshot: false,
      latestStates: []
    )

    XCTAssertTrue(
      HomeAssistantStateStream.shouldReconnect(
        after: HomeAssistantAPIError.server(statusCode: 503),
        attempt: attempt
      )
    )
  }

  func testInvalidTokenResponseBeforeFirstConnectionIsTerminal() async throws {
    let fixture = SessionFixture()
    let malformedResponse = QueueHomeAssistantLoader.Result.success(
      Data("not-json".utf8),
      statusCode: 200
    )
    let session = fixture.makeSession(
      apiResponses: [],
      authenticationResponses: [malformedResponse, malformedResponse]
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))
    let source = HomeAssistantStateStream(
      session: session,
      connector: TemperatureSubscriptionConnector(connections: []),
      retryDelays: [.zero]
    )
    let probe = AsyncThrowingStreamTestProbe(await source.stateUpdates())

    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    do {
      _ = try probe.value(at: 0)
      XCTFail("Expected malformed token response to terminate the stream.")
    } catch HomeAssistantAuthenticationError.invalidTokenResponse {
    } catch {
      XCTFail("Unexpected terminal preflight error: \(error)")
    }
  }

  func testRetryDelaySaturatesAtMaximumDuringRepeatedFailures() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connections = (0..<4).map { _ in
      TemperatureSubscriptionConnection(
        messages: [.failure(URLError(.cannotConnectToHost))]
      )
    }
    let sleeper = SaturatingRetrySleeper(blockingAt: 4)
    let source = HomeAssistantStateStream(
      session: session,
      connector: TemperatureSubscriptionConnector(connections: connections),
      retryDelays: [.seconds(1), .seconds(2)],
      sleep: sleeper.sleep
    )
    let probe = AsyncThrowingStreamTestProbe(await source.stateUpdates())

    await fulfillment(of: [sleeper.blocked], timeout: 1)
    sleeper.cancel()
    await probe.cancel()

    XCTAssertEqual(
      sleeper.delays,
      [.seconds(1), .seconds(2), .seconds(2), .seconds(2)]
    )
  }
}

private final class SaturatingRetrySleeper: @unchecked Sendable {
  let blocked = XCTestExpectation(description: "Maximum retry delay reached")
  private let lock = NSLock()
  private let blockingAt: Int
  private var storedDelays: [Duration] = []
  private var continuation: CheckedContinuation<Void, any Error>?

  init(blockingAt: Int) {
    self.blockingAt = blockingAt
  }

  var delays: [Duration] { lock.withLock { storedDelays } }

  func sleep(for delay: Duration) async throws {
    let shouldBlock = lock.withLock {
      storedDelays.append(delay)
      return storedDelays.count == blockingAt
    }
    guard shouldBlock else { return }
    try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      blocked.fulfill()
    }
  }

  func cancel() {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(throwing: CancellationError())
  }
}

import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantEVChargingLiveStoreTests: XCTestCase {
  func testConnectedStreamUpdatesMarksStaleAndRecoversWithoutProgressFlicker() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)

    client.yield(.live(.init(mode: .smart, activity: .charging(powerWatts: 7_100))))
    await waitForValue(store.$activity, matching: .charging(powerWatts: 7_100))
    client.yield(.live(.init(mode: .smart, activity: .charging(powerWatts: 7_024))))
    await waitForValue(store.$activity, matching: .charging(powerWatts: 7_024))
    client.yield(
      .reconnecting(.init(mode: .smart, activity: .charging(powerWatts: 7_024)))
    )
    await waitForValue(store.$problem.compactMap(\.self), matching: .reconnecting)

    XCTAssertEqual(store.mode, .smart)
    XCTAssertEqual(store.activity, .charging(powerWatts: 7_024))
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.isActivityLive)
    XCTAssertFalse(store.showsProgress)

    client.yield(.live(.init(mode: .charging, activity: .charging(powerWatts: 7_100))))
    await waitForValue(store.$isLive, matching: true)
    XCTAssertEqual(store.mode, .charging)
    XCTAssertEqual(store.activity, .charging(powerWatts: 7_100))
    XCTAssertTrue(store.isActivityLive)
    XCTAssertNil(store.problem)
    XCTAssertFalse(store.showsProgress)
    connection.cancel()
    await connection.value
  }

  func testLiveUpdateDuringModeChangeKeepsOptimisticModeAndUpdatesActivity() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .off,
          activity: .connected,
          modeLastUpdated: Date(timeIntervalSince1970: 100)
        )
      )
    )
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .charging(powerWatts: 6_800))))
    await waitForValue(store.$activity, matching: .charging(powerWatts: 6_800))

    XCTAssertEqual(store.mode, .charging)
    XCTAssertFalse(store.showsProgress)
    client.succeedSet(with: .charging)
    await change.value
    client.yield(.live(.init(mode: .off, activity: .charging(powerWatts: 6_900))))
    await waitForValue(
      store.$activity,
      matching: .charging(powerWatts: 6_900)
    )
    client.yield(.live(.init(mode: .off, activity: .charging(powerWatts: 7_000))))
    await waitForValue(
      store.$activity,
      matching: .charging(powerWatts: 7_000)
    )
    XCTAssertEqual(store.mode, .charging)
    XCTAssertEqual(store.activity, .charging(powerWatts: 7_000))
    XCTAssertTrue(store.isActivityLive)
    XCTAssertFalse(store.showsProgress)
    connection.cancel()
    await connection.value
  }

  func testDifferingLiveModeDuringWriteWinsOverRequestConfirmation() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .off,
          activity: .connected,
          modeLastUpdated: Date(timeIntervalSince1970: 100)
        )
      )
    )
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .smart,
          activity: .charging(powerWatts: 7_000),
          modeLastUpdated: Date(timeIntervalSince1970: 102)
        )
      )
    )
    await waitForValue(store.$activity, matching: .charging(powerWatts: 7_000))
    client.yield(
      .live(
        .init(
          mode: .off,
          activity: .connected,
          modeLastUpdated: Date(timeIntervalSince1970: 101)
        )
      )
    )
    await waitForValue(store.$activity, matching: .connected)
    client.succeedSet(with: .charging)
    await change.value

    XCTAssertEqual(store.mode, .smart)
    XCTAssertTrue(store.isLive)
    connection.cancel()
    await connection.value
  }

  func testMatchingLiveConfirmationBeforeRequestCompletionAcceptsLaterExternalMode() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(.live(.init(mode: .charging, activity: .charging(powerWatts: 7_000))))
    await waitForValue(
      store.$activity,
      matching: .charging(powerWatts: 7_000)
    )
    client.succeedSet(with: .charging)
    await change.value
    client.yield(.live(.init(mode: .smart, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .smart)

    XCTAssertEqual(store.mode, .smart)
    XCTAssertTrue(store.isLive)
    connection.cancel()
    await connection.value
  }

  func testLiveRequestedModeWinsOverOlderRequestConfirmationWithoutFailure() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(.live(.init(mode: .charging, activity: .charging(powerWatts: 7_000))))
    await waitForValue(store.$activity, matching: .charging(powerWatts: 7_000))
    client.succeedSet(with: .off)
    await change.value

    XCTAssertEqual(store.mode, .charging)
    XCTAssertTrue(store.isLive)
    XCTAssertNil(store.problem)
    connection.cancel()
    await connection.value
  }

  func testStaleNonLiveSnapshotsDoNotOverwriteConfirmedMode() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.succeedSet(with: .charging)
    await change.value
    client.yield(.reconnecting(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$problem.compactMap(\.self), matching: .reconnecting)
    XCTAssertEqual(store.mode, .charging)

    client.yield(.unavailable(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$problem.compactMap(\.self), matching: .invalidResponse)
    XCTAssertEqual(store.mode, .charging)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.isActivityLive)
    connection.cancel()
    await connection.value
  }

  func testModeChangeCompletionDoesNotRestoreLivenessWhileReconnecting() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(.reconnecting(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$problem.compactMap(\.self), matching: .reconnecting)
    client.succeedSet(with: .charging)
    await change.value

    XCTAssertEqual(store.mode, .charging)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.isActivityLive)
    XCTAssertFalse(store.canSelectMode)
    XCTAssertEqual(store.problem, .reconnecting)
    connection.cancel()
    await connection.value
  }

  private func waitForValue<P: Publisher>(
    _ publisher: P,
    matching expectedValue: P.Output
  ) async where P.Output: Equatable, P.Failure == Never {
    let published = expectation(description: "Expected live store value published")
    let subscription = publisher.filter { $0 == expectedValue }.prefix(1).sink { _ in
      published.fulfill()
    }
    await fulfillment(of: [published], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  private var credentials: HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(string: "https://home.example")
        ?? URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

final class StreamingEVChargingClient:
  HomeAssistantEVCharging, @unchecked Sendable
{
  let providesContinuousUpdates = true

  let started = XCTestExpectation(description: "EV charging stream started")
  let setStarted = XCTestExpectation(description: "EV charging mode change started")
  let loadStarted = XCTestExpectation(description: "EV charging reconciliation started")

  private let lock = NSLock()
  private var continuation:
    AsyncThrowingStream<
      HomeAssistantEVChargingUpdate, any Error
    >.Continuation?
  private var setContinuation: CheckedContinuation<HomeAssistantEVChargingMode, any Error>?
  private var loadContinuation: CheckedContinuation<HomeAssistantEVChargingSnapshot, any Error>?
  private var nextStreamStart: XCTestExpectation?

  func evChargingUpdates() -> AsyncThrowingStream<
    HomeAssistantEVChargingUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      let nextStreamStart = lock.withLock {
        self.continuation = continuation
        let expectation = self.nextStreamStart
        self.nextStreamStart = nil
        return expectation
      }
      started.fulfill()
      nextStreamStart?.fulfill()
    }
  }

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw StreamingEVChargingError.unexpectedRequest
  }

  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    loadStarted.fulfill()
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        loadContinuation = continuation
      }
    }
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    setStarted.fulfill()
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        setContinuation = continuation
      }
    }
  }

  func yield(_ update: HomeAssistantEVChargingUpdate) {
    let continuation = lock.withLock { continuation }
    continuation?.yield(update)
  }

  func finishUpdates() {
    let continuation = lock.withLock { continuation }
    continuation?.finish()
  }

  func expectNextStreamStart() -> XCTestExpectation {
    let expectation = XCTestExpectation(description: "EV charging stream restarted")
    lock.withLock {
      nextStreamStart = expectation
    }
    return expectation
  }

  func succeedSet(with mode: HomeAssistantEVChargingMode) {
    let continuation = lock.withLock {
      let continuation = setContinuation
      setContinuation = nil
      return continuation
    }
    continuation?.resume(returning: mode)
  }

  func succeedLoad(with snapshot: HomeAssistantEVChargingSnapshot) {
    let continuation = lock.withLock {
      let continuation = loadContinuation
      loadContinuation = nil
      return continuation
    }
    continuation?.resume(returning: snapshot)
  }
}

private enum StreamingEVChargingError: Error {
  case unexpectedRequest
}

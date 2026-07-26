import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantAutomaticDiscoveryTests: XCTestCase {
  func testStartsWhenUnconfiguredAndPreselectsSingleHome() async {
    let discovery = AutomaticDiscoveryTestSource()
    let store = HomeAssistantSetupStore(discovery: discovery)
    defer { store.stopDiscovery() }

    XCTAssertEqual(store.step, .introduction)
    XCTAssertFalse(discovery.hasSubscriber)

    let instancesChanged = expectation(description: "Discovered instances published")
    let subscription = store.$instances.dropFirst().sink { _ in
      instancesChanged.fulfill()
    }
    store.startDiscoveryIfUnconfigured()
    await fulfillment(of: [discovery.started], timeout: 1)
    discovery.send(snapshot(instance("home", name: "Home")))
    await fulfillment(of: [instancesChanged], timeout: 1)

    XCTAssertEqual(store.step, .chooseServer)
    XCTAssertEqual(store.selectedInstanceID, "home")
    withExtendedLifetime(subscription) {}
  }

  func testDoesNotInterruptManualEntry() {
    let discovery = AutomaticDiscoveryTestSource()
    let store = HomeAssistantSetupStore(discovery: discovery)
    store.showManualEntry()

    store.startDiscoveryIfUnconfigured()

    XCTAssertEqual(store.step, .manualEntry)
    XCTAssertFalse(discovery.hasSubscriber)
  }

  func testRestartsAStoppedServerSearch() async {
    let discovery = AutomaticDiscoveryTestSource()
    discovery.cancelled.expectedFulfillmentCount = 2
    let store = HomeAssistantSetupStore(discovery: discovery)
    store.startDiscovery()
    await fulfillment(of: [discovery.started], timeout: 1)
    store.stopDiscovery()

    store.startDiscoveryIfUnconfigured()

    await fulfillment(of: [discovery.restarted], timeout: 1)
    XCTAssertEqual(store.step, .chooseServer)
    XCTAssertTrue(store.isSearching)
    store.stopDiscovery()
    await fulfillment(of: [discovery.cancelled], timeout: 1)
  }

  func testCancelledRestoreCannotEnableAutomaticDiscovery() async {
    let discovery = AutomaticDiscoveryTestSource()
    let connection = SuspendedRestoreConnection()
    let store = HomeAssistantSetupStore(
      discovery: discovery,
      connection: connection
    )
    let restore = Task {
      await store.restoreSavedConnection()
    }
    await fulfillment(of: [connection.restoreStarted], timeout: 1)

    restore.cancel()
    connection.completeRestore()

    let canAutomaticallyDiscover = await restore.value
    if canAutomaticallyDiscover {
      store.startDiscoveryIfUnconfigured()
    }
    XCTAssertFalse(canAutomaticallyDiscover)
    XCTAssertFalse(discovery.hasSubscriber)
  }

  private func instance(_ id: String, name: String) -> HomeAssistantInstance {
    HomeAssistantInstance(
      id: id,
      name: name,
      version: "2026.7.2",
      internalURL: URL(string: "http://\(id).local:8123"),
      externalURL: URL(string: "https://\(id).example.com"),
      isOnboarding: false
    )
  }

  private func snapshot(
    _ instances: HomeAssistantInstance...
  ) -> HomeAssistantDiscoverySnapshot {
    HomeAssistantDiscoverySnapshot(instances: instances, issues: [])
  }
}

@MainActor
private final class SuspendedRestoreConnection: HomeAssistantConnecting {
  let restoreStarted = XCTestExpectation(description: "Connection restore started")
  private var restoreContinuation: CheckedContinuation<HomeAssistantCredentials?, any Error>?

  func connect(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    throw HomeAssistantAuthenticationError.presentationUnavailable
  }

  func restore() async throws -> HomeAssistantCredentials? {
    restoreStarted.fulfill()
    return try await withCheckedThrowingContinuation { continuation in
      restoreContinuation = continuation
    }
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    throw HomeAssistantAPIError.noCredentials
  }

  func disconnect() async throws {}

  func cancel() {}

  func completeRestore() {
    restoreContinuation?.resume(returning: nil)
    restoreContinuation = nil
  }
}

private final class AutomaticDiscoveryTestSource:
  HomeAssistantDiscovering, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Discovery started")
  let restarted = XCTestExpectation(description: "Discovery restarted")
  let cancelled = XCTestExpectation(description: "Discovery cancelled")
  var hasSubscriber: Bool {
    lock.withLock { !continuations.isEmpty }
  }

  private let lock = NSLock()
  private var continuations:
    [AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error>.Continuation] = []

  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { continuation in
      let subscriptionIndex = lock.withLock {
        continuations.append(continuation)
        return continuations.count - 1
      }
      continuation.onTermination = { [cancelled] _ in
        cancelled.fulfill()
      }
      if subscriptionIndex == 0 {
        started.fulfill()
      } else {
        restarted.fulfill()
      }
    }
  }

  func send(_ snapshot: HomeAssistantDiscoverySnapshot) {
    lock.withLock {
      continuations.last
    }?.yield(snapshot)
  }
}

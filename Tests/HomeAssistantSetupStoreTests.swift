import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantSetupStoreTests: XCTestCase {
  func testDiscoveryStartsOnlyAfterUserActionAndPreselectsSingleHome() async {
    let discovery = ControlledSetupDiscovery()
    let store = HomeAssistantSetupStore(discovery: discovery)
    defer { store.stopDiscovery() }

    XCTAssertEqual(store.step, .introduction)
    XCTAssertFalse(discovery.hasSubscriber)

    let instancesChanged = expectation(description: "Discovered instances published")
    let subscription = store.$instances.dropFirst().sink { _ in
      instancesChanged.fulfill()
    }
    store.startDiscovery()
    await fulfillment(of: [discovery.started], timeout: 1)
    discovery.send(snapshot(instance("home", name: "Home")))
    await fulfillment(of: [instancesChanged], timeout: 1)

    XCTAssertEqual(store.step, .chooseServer)
    XCTAssertEqual(store.selectedInstanceID, "home")
    withExtendedLifetime(subscription) {}
  }

  func testMultipleHomesRequireExplicitSelection() async {
    let discovery = ControlledSetupDiscovery()
    let store = HomeAssistantSetupStore(discovery: discovery)
    defer { store.stopDiscovery() }
    let instancesChanged = expectation(description: "Discovered instances published")
    instancesChanged.expectedFulfillmentCount = 2
    let subscription = store.$instances.dropFirst().sink { _ in
      instancesChanged.fulfill()
    }
    store.startDiscovery()
    await fulfillment(of: [discovery.started], timeout: 1)
    discovery.send(snapshot(instance("one", name: "One")))
    discovery.send(
      snapshot(
        instance("one", name: "One"),
        instance("two", name: "Two")
      )
    )
    await fulfillment(of: [instancesChanged], timeout: 1)

    XCTAssertNil(store.selectedInstanceID)
    store.selectInstance(id: "two")
    store.confirmSelectedInstance()

    guard case .unencryptedWarning(let candidate) = store.step else {
      return XCTFail("Expected an unencrypted connection warning.")
    }
    XCTAssertEqual(candidate.instanceID, "two")
    store.acceptUnencryptedConnection()
    XCTAssertEqual(store.step, .confirmation(candidate))
    withExtendedLifetime(subscription) {}
  }

  func testManualValidationPreservesInputAndReportsSpecificError() {
    let store = HomeAssistantSetupStore(discovery: ControlledSetupDiscovery())
    store.showManualEntry()
    store.updateManualAddress("https://example.com/api/states")

    store.validateManualAddress()

    XCTAssertEqual(store.manualAddress, "https://example.com/api/states")
    XCTAssertEqual(store.manualValidationError, .pointsToEndpoint)
    XCTAssertEqual(store.step, .manualEntry)
  }

  func testManualHTTPRequiresExplicitWarningConfirmation() {
    let store = HomeAssistantSetupStore(discovery: ControlledSetupDiscovery())
    store.showManualEntry()
    store.updateManualAddress("http://homeassistant.local:8123")

    store.validateManualAddress()

    guard case .unencryptedWarning(let candidate) = store.step else {
      return XCTFail("Expected an unencrypted connection warning.")
    }
    XCTAssertEqual(candidate.activeURL, URL(string: "http://homeassistant.local:8123"))

    store.acceptUnencryptedConnection()

    XCTAssertEqual(store.step, .confirmation(candidate))
  }

  func testRejectingDiscoveredHTTPReturnsToServerChoice() async {
    let discovery = ControlledSetupDiscovery()
    let store = HomeAssistantSetupStore(discovery: discovery)
    defer { store.stopDiscovery() }
    let instancesChanged = expectation(description: "Discovered instances published")
    let subscription = store.$instances.dropFirst().sink { _ in
      instancesChanged.fulfill()
    }
    store.startDiscovery()
    await fulfillment(of: [discovery.started], timeout: 1)
    discovery.send(snapshot(instance("home", name: "Home")))
    await fulfillment(of: [instancesChanged], timeout: 1)

    store.confirmSelectedInstance()
    store.rejectUnencryptedConnection()

    XCTAssertEqual(store.step, .chooseServer)
    withExtendedLifetime(subscription) {}
  }

  func testUnresolvedAndHTTPExternalOnlyHomesCannotContinue() async {
    let discovery = ControlledSetupDiscovery()
    let store = HomeAssistantSetupStore(discovery: discovery)
    defer { store.stopDiscovery() }
    let instancesChanged = expectation(description: "Discovered instances published")
    instancesChanged.expectedFulfillmentCount = 2
    let subscription = store.$instances.dropFirst().sink { _ in
      instancesChanged.fulfill()
    }
    store.startDiscovery()
    await fulfillment(of: [discovery.started], timeout: 1)
    discovery.send(snapshot(instanceWithoutUsableURL("pending", externalURL: nil)))
    discovery.send(
      snapshot(
        instanceWithoutUsableURL(
          "remote",
          externalURL: URL(string: "http://remote.example.com")
        )
      )
    )
    await fulfillment(of: [instancesChanged], timeout: 1)

    XCTAssertFalse(store.canConfirmSelectedInstance)
    store.confirmSelectedInstance()
    XCTAssertEqual(store.step, .chooseServer)
    withExtendedLifetime(subscription) {}
  }

  func testManualChoiceStartsDiscoveryAndAuthenticationCancellationRestoresConfirmation() async {
    let discovery = ControlledSetupDiscovery()
    let store = HomeAssistantSetupStore(discovery: discovery)
    store.showManualEntry()

    store.showDiscoveredHomes()

    await fulfillment(of: [discovery.started], timeout: 1)
    XCTAssertTrue(store.isSearching)
    store.stopDiscovery()
    store.showManualEntry()
    store.updateManualAddress("https://home.example.com")
    store.validateManualAddress()
    guard case .confirmation(let candidate) = store.step else {
      return XCTFail("Expected confirmation.")
    }
    store.requestAuthentication()
    store.cancelAuthentication()
    XCTAssertEqual(store.step, .confirmation(candidate))
  }

  func testOnboardingHomeCannotAdvanceToAuthentication() async {
    let discovery = ControlledSetupDiscovery()
    let store = HomeAssistantSetupStore(discovery: discovery)
    defer { store.stopDiscovery() }
    let instancesChanged = expectation(description: "Discovered instances published")
    let subscription = store.$instances.dropFirst().sink { _ in
      instancesChanged.fulfill()
    }
    store.startDiscovery()
    await fulfillment(of: [discovery.started], timeout: 1)
    let onboarding = instance("home", name: "Home", isOnboarding: true)
    discovery.send(snapshot(onboarding))
    await fulfillment(of: [instancesChanged], timeout: 1)

    store.confirmSelectedInstance()

    XCTAssertEqual(store.step, .onboardingRequired(onboarding))
    withExtendedLifetime(subscription) {}
  }

  func testStoppingSetupCancelsDiscovery() async {
    let discovery = ControlledSetupDiscovery()
    let store = HomeAssistantSetupStore(discovery: discovery)
    store.startDiscovery()
    await fulfillment(of: [discovery.started], timeout: 1)

    store.cancel()

    await fulfillment(of: [discovery.cancelled], timeout: 1)
    XCTAssertEqual(store.step, .cancelled)
  }

  func testPermissionDenialHasDistinctRecoveryState() async {
    let discovery = ControlledSetupDiscovery()
    let store = HomeAssistantSetupStore(discovery: discovery)
    defer { store.stopDiscovery() }
    let problemChanged = expectation(description: "Discovery problem published")
    let subscription = store.$discoveryProblem.compactMap { $0 }.sink { _ in
      problemChanged.fulfill()
    }
    store.startDiscovery()
    await fulfillment(of: [discovery.started], timeout: 1)

    discovery.fail(with: HomeAssistantDiscoveryError.permissionDenied)
    await fulfillment(of: [problemChanged], timeout: 1)

    XCTAssertEqual(store.discoveryProblem, .permissionDenied)
    XCTAssertFalse(store.isSearching)
    withExtendedLifetime(subscription) {}
  }

  func testReplacingDiscoveryIgnoresLateResultsFromOldStream() async {
    let discovery = ControlledSetupDiscovery()
    discovery.cancelled.expectedFulfillmentCount = 2
    let store = HomeAssistantSetupStore(discovery: discovery)
    let currentInstancesChanged = expectation(description: "Current discovery published")
    let subscription = store.$instances.dropFirst().sink { instances in
      if instances.first?.id == "current" {
        currentInstancesChanged.fulfill()
      }
    }
    store.startDiscovery()
    await fulfillment(of: [discovery.started], timeout: 1)
    store.startDiscovery()
    await fulfillment(of: [discovery.restarted], timeout: 1)

    discovery.send(snapshot(instance("stale", name: "Stale")), to: 0)
    discovery.send(snapshot(instance("current", name: "Current")), to: 1)
    await fulfillment(of: [currentInstancesChanged], timeout: 1)

    XCTAssertEqual(store.instances.map(\.id), ["current"])
    store.stopDiscovery()
    await fulfillment(of: [discovery.cancelled], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  func testReleasingStoreCancelsDiscovery() async {
    let discovery = ControlledSetupDiscovery()
    weak var weakStore: HomeAssistantSetupStore?
    do {
      let store = HomeAssistantSetupStore(discovery: discovery)
      weakStore = store
      store.startDiscovery()
      await fulfillment(of: [discovery.started], timeout: 1)
    }

    await fulfillment(of: [discovery.cancelled], timeout: 1)
    XCTAssertNil(weakStore)
  }

  private func instance(
    _ id: String,
    name: String,
    isOnboarding: Bool = false
  ) -> HomeAssistantInstance {
    HomeAssistantInstance(
      id: id,
      name: name,
      version: "2026.7.2",
      internalURL: URL(string: "http://\(id).local:8123"),
      externalURL: URL(string: "https://\(id).example.com"),
      isOnboarding: isOnboarding
    )
  }

  private func snapshot(
    _ instances: HomeAssistantInstance...
  ) -> HomeAssistantDiscoverySnapshot {
    HomeAssistantDiscoverySnapshot(instances: instances, issues: [])
  }

  private func instanceWithoutUsableURL(
    _ id: String,
    externalURL: URL?
  ) -> HomeAssistantInstance {
    HomeAssistantInstance(
      id: id,
      name: "Home",
      version: nil,
      internalURL: nil,
      externalURL: externalURL,
      isOnboarding: false
    )
  }
}

private final class ControlledSetupDiscovery: HomeAssistantDiscovering, @unchecked Sendable {
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

  func send(_ snapshot: HomeAssistantDiscoverySnapshot, to index: Int? = nil) {
    lock.withLock {
      index.map { continuations[$0] } ?? continuations.last
    }?.yield(snapshot)
  }

  func fail(with error: any Error) {
    lock.withLock {
      continuations.last
    }?.finish(throwing: error)
  }
}

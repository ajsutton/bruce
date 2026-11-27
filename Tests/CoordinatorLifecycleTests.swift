import Foundation
import XCTest

@testable import Bruce

@MainActor
final class CoordinatorLifecycleTests: XCTestCase {
  func testCancelledServerStatusTaskDoesNotOpenFeed() async {
    let source = ControlledStateSource()
    let coordinator = makeCoordinator(serverUpdates: { await source.stateUpdates() })

    await coordinator.synchronize(with: .ready(credentials))
    await coordinator.synchronize(with: .signedOut)
    await Task.yield()

    XCTAssertEqual(source.subscriptionCount, 0)
  }

  func testCoordinatorTeardownCancelsActiveServerStatusFeed() async {
    let source = ControlledStateSource()
    var coordinator: HomeAssistantObservationCoordinator? = makeCoordinator(
      serverUpdates: { await source.stateUpdates() }
    )
    await coordinator?.synchronize(with: .ready(credentials))
    await fulfillment(of: [source.started], timeout: 1)

    coordinator = nil

    await fulfillment(of: [source.cancelled], timeout: 1)
    XCTAssertTrue(source.isCancelled)
  }

  func testReadyWhileSuspendedStartsFreshObservationsOnForeground() async {
    let source = ControlledStateSource()
    let temperatureStore = HomeAssistantTemperatureStore(
      loader: LifecycleTemperatureLoader()
    )
    let coordinator = HomeAssistantObservationCoordinator(
      temperatureStore: temperatureStore,
      chargingStore: HomeAssistantEVChargingStore(
        client: StreamingEVChargingClient()
      ),
      garageDoorStore: HomeAssistantGarageDoorStore(loader: TestGarageDoorLoader()),
      homeEnergyStore: HomeAssistantHomeEnergyStore(loader: LifecycleEnergyLoader()),
      serverUpdates: { await source.stateUpdates() }
    )
    let inactiveRegistered = expectation(description: "Inactive observation registered")
    let inactive = Task {
      await coordinator.observeUpdates(while: false) {
        inactiveRegistered.fulfill()
      }
    }
    await fulfillment(of: [inactiveRegistered], timeout: 1)
    await coordinator.synchronize(with: .ready(credentials))
    XCTAssertEqual(source.subscriptionCount, 0)

    let activeRegistered = expectation(description: "Active observation registered")
    let active = Task {
      await coordinator.observeUpdates(while: true) {
        activeRegistered.fulfill()
      }
    }
    await fulfillment(of: [activeRegistered, source.started], timeout: 1)

    XCTAssertEqual(source.subscriptionCount, 1)
    XCTAssertTrue(temperatureStore.isLive)
    active.cancel()
    inactive.cancel()
    await active.value
    await inactive.value
  }

  func testForegroundCycleReusesServerObservationAndTeardownCancelsIt() async {
    let source = ControlledStateSource()
    var coordinator: HomeAssistantObservationCoordinator? = makeCoordinator(
      serverUpdates: { await source.stateUpdates() }
    )
    await coordinator?.synchronize(with: .ready(credentials))
    await fulfillment(of: [source.started], timeout: 1)
    let firstActive = Task { await coordinator?.observeUpdates(while: true) }
    await Task.yield()
    firstActive.cancel()
    await firstActive.value

    let secondActive = Task { await coordinator?.observeUpdates(while: true) }
    await Task.yield()

    XCTAssertEqual(source.subscriptionCount, 1)
    secondActive.cancel()
    await secondActive.value
    coordinator = nil
    await fulfillment(of: [source.cancelled], timeout: 1)
    XCTAssertTrue(source.isCancelled)
  }

  func testForegroundReplacesRetainedSocketWhenActivityRegistrationsOverlap() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let coordinator = makeCoordinator(
      serverUpdates: { await supervisor.stateUpdates() },
      sendWakeHint: { await supervisor.receiveWakeHint() }
    )
    let registered = expectation(description: "Initial activity registered")
    let initialActivity = Task {
      await coordinator.observeUpdates(while: true) { registered.fulfill() }
    }
    defer { initialActivity.cancel() }
    await fulfillment(of: [registered], timeout: 5)
    await coordinator.synchronize(with: .ready(credentials))
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)

    // Retain the old registration to model SwiftUI starting foreground work before its
    // cancelled task has finished unregistering. No suspension callback reaches the feed.
    let foregroundActivity = Task { await coordinator.observeUpdates(while: true) }
    defer { foregroundActivity.cancel() }
    await fulfillment(of: [probe.received(at: 2)], timeout: 5)

    XCTAssertTrue(first.isCancelled)
    XCTAssertEqual(connector.connectionCount, 2)
    XCTAssertEqual(try probe.value(at: 1).phase, .reconnecting)
    XCTAssertEqual(try probe.value(at: 2).phase, .live)
    XCTAssertEqual(
      try probe.value(at: 2).states.first?.temperatureReading(unit: "°C", metadata: nil)?.value, 23
    )
    initialActivity.cancel()
    foregroundActivity.cancel()
    await initialActivity.value
    await foregroundActivity.value
    await probe.cancel()
  }

  func testForegroundSkipsPendingRetryWithoutWaitingForBackoff() async throws {
    let fixture = SupervisorFixture(snapshotValues: [21, 23])
    try await fixture.install()
    let first = ScriptedHomeAssistantConnection()
    let replacement = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [first, replacement])
    let clock = ControlledConnectionClock()
    let supervisor = HomeAssistantConnectionSupervisor(
      session: fixture.session,
      connector: connector,
      credentialEvents: fixture.credentialEvents,
      retryPolicy: HomeAssistantConnectionRetryPolicy(
        initialWindow: 60, maximumWindow: 60, randomUnit: { 1 }
      ),
      clock: clock.connectionClock
    )
    let coordinator = makeCoordinator(
      serverUpdates: { await supervisor.stateUpdates() },
      sendWakeHint: { await supervisor.receiveWakeHint() }
    )
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())
    await fulfillment(of: [probe.received(at: 0)], timeout: 5)
    let backoff = clock.expectSleep(.seconds(60))
    first.fail(with: URLError(.networkConnectionLost))
    await fulfillment(of: [backoff, probe.received(at: 1)], timeout: 5)

    let foregroundActivity = Task { await coordinator.observeUpdates(while: true) }
    defer { foregroundActivity.cancel() }
    await fulfillment(of: [probe.received(at: 2)], timeout: 5)

    XCTAssertEqual(connector.connectionCount, 2)
    XCTAssertEqual(try probe.value(at: 2).phase, .live)
    foregroundActivity.cancel()
    await foregroundActivity.value
    await probe.cancel()
  }

  private func makeCoordinator(
    serverUpdates:
      @escaping @Sendable () async -> HomeAssistantBufferedUpdateStream<
        HomeAssistantStateUpdate
      >,
    sendWakeHint: @escaping @Sendable () async -> Void = {}
  ) -> HomeAssistantObservationCoordinator {
    HomeAssistantObservationCoordinator(
      temperatureStore: HomeAssistantTemperatureStore(
        loader: LifecycleTemperatureLoader()
      ),
      chargingStore: HomeAssistantEVChargingStore(
        client: StreamingEVChargingClient()
      ),
      garageDoorStore: HomeAssistantGarageDoorStore(
        loader: TestGarageDoorLoader()
      ),
      homeEnergyStore: HomeAssistantHomeEnergyStore(
        loader: LifecycleEnergyLoader()
      ),
      sendWakeHint: sendWakeHint,
      serverUpdates: serverUpdates
    )
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

private struct LifecycleTemperatureLoader: HomeAssistantTemperatureLoading {
  func temperatureUpdates() -> HomeAssistantTemperatureUpdateStream {
    HomeAssistantTemperatureUpdateStream { continuation in
      continuation.yield(.live([]))
    }
  }
}

private struct LifecycleEnergyLoader: HomeAssistantHomeEnergyLoading {
  let providesContinuousEnergyUpdates = true

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }

  func homeEnergyUpdates() -> HomeAssistantHomeEnergyUpdateStream {
    HomeAssistantHomeEnergyUpdateStream { continuation in
      continuation.yield(.live(.unavailable))
    }
  }
}

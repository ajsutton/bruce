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

  private func makeCoordinator(
    serverUpdates:
      @escaping @Sendable () async -> HomeAssistantBufferedUpdateStream<
        HomeAssistantStateUpdate
      >
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

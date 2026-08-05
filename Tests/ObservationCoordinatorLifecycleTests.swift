import Foundation
import XCTest

@testable import Bruce

@MainActor
final class ObservationCoordinatorLifecycleTests: XCTestCase {
  func testConnectedObservationCancelledBeforeStartDoesNotOpenStream() async {
    let loader = ObservationTestTemperatureLoader()
    loader.started.isInverted = true
    let coordinator = makeCoordinator(temperatureLoader: loader)

    let connection = Task {
      await coordinator.synchronize(with: .connected(credentials))
    }
    connection.cancel()
    await coordinator.synchronize(with: .disconnected)
    await connection.value

    await fulfillment(of: [loader.started], timeout: 0.1)
  }

  func testCoordinatorTeardownCancelsOwnedObservationTasks() async {
    let loader = ObservationTestTemperatureLoader()
    var coordinator: HomeAssistantObservationCoordinator? = makeCoordinator(
      temperatureLoader: loader
    )
    weak let weakCoordinator = coordinator
    await coordinator?.synchronize(with: .connected(credentials))
    await fulfillment(of: [loader.started], timeout: 1)

    coordinator = nil

    await fulfillment(of: [loader.cancelled], timeout: 1)
    XCTAssertNil(weakCoordinator)
  }

  func testConnectionTransitionWaitsForSharedFeedReset() async {
    let loader = ObservationTestTemperatureLoader()
    let reset = ControlledStateFeedReset()
    let coordinator = makeCoordinator(
      temperatureLoader: loader,
      resetStateFeed: reset.call
    )
    let transition = Task {
      await coordinator.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [reset.started], timeout: 1)

    XCTAssertEqual(loader.startCount, 0)

    reset.resume()
    await transition.value
    await fulfillment(of: [loader.started], timeout: 1)
    XCTAssertEqual(loader.startCount, 1)
  }

  func testCancelledTransitionCanRetryTheSameConnection() async {
    let loader = ObservationTestTemperatureLoader()
    let reset = ControlledStateFeedReset()
    let coordinator = makeCoordinator(
      temperatureLoader: loader,
      resetStateFeed: reset.call
    )
    let cancelledTransition = Task {
      await coordinator.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [reset.started], timeout: 1)
    cancelledTransition.cancel()
    reset.resume()
    await cancelledTransition.value

    XCTAssertEqual(loader.startCount, 0)

    await coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [loader.started], timeout: 1)
    XCTAssertEqual(loader.startCount, 1)
  }

  func testBlockedReplacementCanReturnToTheActiveConnection() async {
    let loader = ObservationTestTemperatureLoader()
    loader.started.assertForOverFulfill = false
    let reset = ControlledStateFeedReset(blockingCall: 2)
    let coordinator = makeCoordinator(
      temperatureLoader: loader,
      resetStateFeed: reset.call
    )
    await coordinator.synchronize(with: .connected(credentials))
    let replacement = Task {
      await coordinator.synchronize(with: .connected(replacementCredentials))
    }
    await fulfillment(of: [reset.started], timeout: 1)
    let restarted = loader.expectStartCount(2)

    await coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [restarted], timeout: 1)
    replacement.cancel()
    reset.resume()
    await replacement.value

    XCTAssertEqual(loader.startCount, 2)
  }

  func testCancelledReplacementCanRetryThePreviousConnection() async {
    let loader = ObservationTestTemperatureLoader()
    loader.started.assertForOverFulfill = false
    let reset = ControlledStateFeedReset(blockingCall: 2)
    let coordinator = makeCoordinator(
      temperatureLoader: loader,
      resetStateFeed: reset.call
    )
    await coordinator.synchronize(with: .connected(credentials))
    let replacement = Task {
      await coordinator.synchronize(with: .connected(replacementCredentials))
    }
    await fulfillment(of: [reset.started], timeout: 1)
    replacement.cancel()
    reset.resume()
    await replacement.value
    let restarted = loader.expectStartCount(2)

    await coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [restarted], timeout: 1)

    XCTAssertEqual(loader.startCount, 2)
  }

  func testRefreshIsIgnoredDuringConnectionTransition() async {
    let loader = ObservationTestTemperatureLoader()
    loader.started.assertForOverFulfill = false
    let reset = ControlledStateFeedReset(blockingCall: 2)
    let refresh = ControlledStateFeedRefresh()
    refresh.started.isInverted = true
    let coordinator = makeCoordinator(
      temperatureLoader: loader,
      refreshStateFeed: refresh.call,
      resetStateFeed: reset.call
    )
    await coordinator.synchronize(with: .connected(credentials))
    let replacement = Task {
      await coordinator.synchronize(with: .connected(replacementCredentials))
    }
    await fulfillment(of: [reset.started], timeout: 1)

    await coordinator.refresh()
    await fulfillment(of: [refresh.started], timeout: 0.1)

    let replacementStarted = loader.expectStartCount(2)
    reset.resume()
    await replacement.value
    await fulfillment(of: [replacementStarted], timeout: 1)
    XCTAssertEqual(loader.startCount, 2)
  }

  func testSupersededRefreshCannotRestartReplacementConnection() async {
    let loader = ObservationTestTemperatureLoader()
    loader.started.assertForOverFulfill = false
    let refresh = ControlledStateFeedRefresh()
    let coordinator = makeCoordinator(
      temperatureLoader: loader,
      refreshStateFeed: refresh.call
    )
    await coordinator.synchronize(with: .connected(credentials))
    let secondStart = loader.expectStartCount(2)
    let refreshTask = Task { await coordinator.refresh() }
    await fulfillment(of: [refresh.started], timeout: 1)

    await coordinator.synchronize(with: .connected(replacementCredentials))
    await fulfillment(of: [secondStart], timeout: 1)
    let unexpectedRestart = loader.expectStartCount(3)
    unexpectedRestart.isInverted = true
    refresh.resume()
    await refreshTask.value
    await fulfillment(of: [unexpectedRestart], timeout: 0.1)

    XCTAssertEqual(loader.startCount, 2)
  }

  private func makeCoordinator(
    temperatureLoader: ObservationTestTemperatureLoader,
    refreshStateFeed: @escaping @Sendable () async -> Bool = { false },
    resetStateFeed: @escaping @Sendable () async -> Void = {}
  ) -> HomeAssistantObservationCoordinator {
    HomeAssistantObservationCoordinator(
      temperatureStore: HomeAssistantTemperatureStore(loader: temperatureLoader),
      chargingStore: HomeAssistantEVChargingStore(client: ObservationTestChargingClient()),
      garageDoorStore: HomeAssistantGarageDoorStore(
        loader: TestGarageDoorLoader()
      ),
      homeEnergyStore: HomeAssistantHomeEnergyStore(loader: ObservationTestEnergyLoader()),
      refreshStateFeed: refreshStateFeed,
      resetStateFeed: resetStateFeed
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

  private var replacementCredentials: HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "other-home",
      instanceName: "Other Home",
      internalURL: URL(string: "http://other.local:8123"),
      externalURL: URL(string: "https://other.example"),
      lastSuccessfulURL: URL(string: "https://other.example")
        ?? URL(fileURLWithPath: "/"),
      accessToken: "other-access",
      refreshToken: "other-refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

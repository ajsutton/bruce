import Foundation
import XCTest

@testable import Bruce

@MainActor
final class ObservationActivityRaceTests: XCTestCase {
  func testSuspensionInvalidatesBlockedRefresh() async {
    let loader = ObservationTestTemperatureLoader()
    loader.started.assertForOverFulfill = false
    let refresh = ControlledStateFeedRefresh()
    let coordinator = makeCoordinator(
      temperatureLoader: loader,
      refreshStateFeed: refresh.call
    )
    await coordinator.synchronize(with: .ready(credentials))
    let refreshTask = Task { await coordinator.refresh() }
    await fulfillment(of: [refresh.started], timeout: 1)
    let suspended = expectation(description: "Inactive window registered")
    let inactiveWindow = Task {
      await coordinator.observeUpdates(
        while: false,
        registrationDidBegin: { suspended.fulfill() }
      )
    }
    await fulfillment(of: [suspended, loader.cancelled], timeout: 1)
    let unexpectedRestart = loader.expectStartCount(2)
    unexpectedRestart.isInverted = true

    refresh.resume()
    await refreshTask.value
    await fulfillment(of: [unexpectedRestart], timeout: 0.1)

    XCTAssertEqual(loader.startCount, 1)
    inactiveWindow.cancel()
    await inactiveWindow.value
  }

  func testActivationDuringTransitionWaitsForReplacementConnection() async {
    let loader = ObservationTestTemperatureLoader()
    loader.started.assertForOverFulfill = false
    let reset = ControlledStateFeedReset(blockingCall: 3)
    let coordinator = makeCoordinator(
      temperatureLoader: loader,
      resetStateFeed: reset.call
    )
    await coordinator.synchronize(with: .ready(credentials))
    let suspended = expectation(description: "Inactive window registered")
    let inactiveWindow = Task {
      await coordinator.observeUpdates(
        while: false,
        registrationDidBegin: { suspended.fulfill() }
      )
    }
    await fulfillment(of: [suspended, loader.cancelled], timeout: 1)
    let replacement = Task {
      await coordinator.synchronize(with: .ready(replacementCredentials))
    }
    await fulfillment(of: [reset.started], timeout: 1)
    let activated = expectation(description: "Active window registered")
    let activeWindow = Task {
      await coordinator.observeUpdates(
        while: true,
        registrationDidBegin: { activated.fulfill() }
      )
    }
    await fulfillment(of: [activated], timeout: 1)
    let prematureStart = loader.expectStartCount(2)
    prematureStart.isInverted = true
    await fulfillment(of: [prematureStart], timeout: 0.1)
    loader.removeStartExpectation(for: 2)
    XCTAssertEqual(loader.startCount, 1)

    let replacementStarted = loader.expectStartCount(2)
    reset.resume()
    await replacement.value
    await fulfillment(of: [replacementStarted], timeout: 1)

    activeWindow.cancel()
    inactiveWindow.cancel()
    await activeWindow.value
    await inactiveWindow.value
  }

  private func makeCoordinator(
    temperatureLoader: ObservationTestTemperatureLoader,
    refreshStateFeed: @escaping @Sendable () async -> Bool = { false },
    resetStateFeed: @escaping @Sendable () async -> Void = {}
  ) -> HomeAssistantObservationCoordinator {
    HomeAssistantObservationCoordinator(
      temperatureStore: HomeAssistantTemperatureStore(loader: temperatureLoader),
      chargingStore: HomeAssistantEVChargingStore(client: ObservationTestChargingClient()),
      garageDoorStore: HomeAssistantGarageDoorStore(loader: TestGarageDoorLoader()),
      homeEnergyStore: HomeAssistantHomeEnergyStore(loader: ObservationTestEnergyLoader()),
      refreshStateFeed: refreshStateFeed,
      resetStateFeed: resetStateFeed
    )
  }

  private var credentials: HomeAssistantCredentials {
    credentials(instanceID: "home")
  }

  private var replacementCredentials: HomeAssistantCredentials {
    credentials(instanceID: "other-home")
  }

  private func credentials(instanceID: String) -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: instanceID,
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

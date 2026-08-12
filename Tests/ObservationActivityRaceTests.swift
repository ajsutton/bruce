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

  func testInvalidatedRefreshCannotClearReplacementRefreshOwnership() async {
    let loader = ObservationTestTemperatureLoader()
    loader.started.assertForOverFulfill = false
    let refresh = SequencedStateFeedRefresh()
    let coordinator = makeCoordinator(
      temperatureLoader: loader,
      refreshStateFeed: refresh.call
    )
    await coordinator.synchronize(with: .ready(credentials))
    let firstRefresh = Task { await coordinator.refresh() }
    await fulfillment(of: [refresh.firstStarted], timeout: 1)
    await coordinator.synchronize(with: .ready(replacementCredentials))
    let secondRefresh = Task { await coordinator.refresh() }
    await fulfillment(of: [refresh.secondStarted], timeout: 1)

    refresh.resumeFirst()
    await firstRefresh.value
    refresh.thirdStarted.isInverted = true
    let thirdRefresh = Task { await coordinator.refresh() }
    await fulfillment(of: [refresh.thirdStarted], timeout: 0.1)

    XCTAssertEqual(refresh.callCount, 2)
    if refresh.callCount == 3 {
      refresh.resumeThird()
    }
    await thirdRefresh.value
    refresh.resumeSecond()
    await secondRefresh.value
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

private final class SequencedStateFeedRefresh: @unchecked Sendable {
  let firstStarted = XCTestExpectation(description: "First refresh started")
  let secondStarted = XCTestExpectation(description: "Second refresh started")
  let thirdStarted = XCTestExpectation(description: "Third refresh started")
  private let lock = NSLock()
  private var continuations: [CheckedContinuation<Bool, Never>] = []

  var callCount: Int { lock.withLock { continuations.count } }

  func call() async -> Bool {
    await withCheckedContinuation { continuation in
      let count = lock.withLock {
        continuations.append(continuation)
        return continuations.count
      }
      switch count {
      case 1: firstStarted.fulfill()
      case 2: secondStarted.fulfill()
      default: thirdStarted.fulfill()
      }
    }
  }

  func resumeFirst() { resume(at: 0) }
  func resumeSecond() { resume(at: 1) }
  func resumeThird() { resume(at: 2) }

  private func resume(at index: Int) {
    let continuation = lock.withLock { continuations[index] }
    continuation.resume(returning: false)
  }
}

import Foundation
import XCTest

@testable import Bruce

@MainActor
final class ObservationCoordinatorLifecycleTests: XCTestCase {
  func testConnectedObservationCancelledBeforeStartDoesNotOpenStream() async {
    let loader = LifecycleTemperatureLoader()
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
    let loader = LifecycleTemperatureLoader()
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
    let loader = LifecycleTemperatureLoader()
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
    let loader = LifecycleTemperatureLoader()
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
    let loader = LifecycleTemperatureLoader()
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
    let loader = LifecycleTemperatureLoader()
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
    let loader = LifecycleTemperatureLoader()
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
    let loader = LifecycleTemperatureLoader()
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
    temperatureLoader: LifecycleTemperatureLoader,
    refreshStateFeed: @escaping @Sendable () async -> Bool = { false },
    resetStateFeed: @escaping @Sendable () async -> Void = {}
  ) -> HomeAssistantObservationCoordinator {
    HomeAssistantObservationCoordinator(
      temperatureStore: HomeAssistantTemperatureStore(loader: temperatureLoader),
      chargingStore: HomeAssistantEVChargingStore(client: LifecycleEVChargingClient()),
      garageDoorStore: HomeAssistantGarageDoorStore(
        loader: TestGarageDoorLoader()
      ),
      homeEnergyStore: HomeAssistantHomeEnergyStore(loader: LifecycleEnergyLoader()),
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

private final class LifecycleTemperatureLoader:
  HomeAssistantTemperatureLoading, @unchecked Sendable
{
  let providesContinuousTemperatureUpdates = true
  let started = XCTestExpectation(description: "Temperature observation started")
  let cancelled = XCTestExpectation(description: "Temperature observation cancelled")
  private let lock = NSLock()
  private var storedStartCount = 0
  private var startExpectations: [Int: XCTestExpectation] = [:]

  var startCount: Int {
    lock.withLock { storedStartCount }
  }

  func expectStartCount(_ count: Int) -> XCTestExpectation {
    let expectation = XCTestExpectation(
      description: "Temperature observation reached \(count) starts"
    )
    let reached = lock.withLock {
      if storedStartCount >= count { return true }
      startExpectations[count] = expectation
      return false
    }
    if reached {
      expectation.fulfill()
    }
    return expectation
  }

  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      let expectation = lock.withLock {
        storedStartCount += 1
        return startExpectations.removeValue(forKey: storedStartCount)
      }
      started.fulfill()
      expectation?.fulfill()
      continuation.onTermination = { _ in
        self.cancelled.fulfill()
      }
    }
  }
}

private final class ControlledStateFeedRefresh: @unchecked Sendable {
  let started = XCTestExpectation(description: "State feed refresh started")
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Bool, Never>?

  func call() async -> Bool {
    started.fulfill()
    return await withCheckedContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
    }
  }

  func resume() {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(returning: false)
  }
}

private final class ControlledStateFeedReset: @unchecked Sendable {
  let started = XCTestExpectation(description: "State feed reset started")
  private let blockingCall: Int
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var callCount = 0

  init(blockingCall: Int = 1) {
    self.blockingCall = blockingCall
  }

  func call() async {
    let shouldBlock = lock.withLock {
      callCount += 1
      return callCount == blockingCall
    }
    guard shouldBlock else { return }
    await withCheckedContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func resume() {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume()
  }
}

private struct LifecycleEVChargingClient: HomeAssistantEVCharging {
  let providesContinuousUpdates = true

  func evChargingUpdates() -> AsyncThrowingStream<
    HomeAssistantEVChargingUpdate, any Error
  > {
    AsyncThrowingStream { _ in }
  }

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw LifecycleObservationError.unexpectedRequest
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    throw LifecycleObservationError.unexpectedRequest
  }
}

private struct LifecycleEnergyLoader: HomeAssistantHomeEnergyLoading {
  let providesContinuousEnergyUpdates = true

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw LifecycleObservationError.unexpectedRequest
  }

  func homeEnergyUpdates() -> AsyncThrowingStream<
    HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>, any Error
  > {
    AsyncThrowingStream { _ in }
  }
}

private enum LifecycleObservationError: Error {
  case unexpectedRequest
}

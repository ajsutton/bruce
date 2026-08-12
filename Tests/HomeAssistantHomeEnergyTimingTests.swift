import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantHomeEnergyTimingTests: XCTestCase {
  func testFastLoadNeverShowsLateProgress() async {
    let loader = ControlledHomeEnergyLoader(requestCount: 1)
    let progressDelay = ControlledHomeEnergyDelay(delayCount: 1)
    let store = HomeAssistantHomeEnergyStore(
      loader: loader,
      snapshot: snapshot(solarPower: 4.2),
      isLive: true,
      progressSleep: { try? await progressDelay.sleep($0) }
    )
    let load = Task { await store.load() }
    await fulfillment(
      of: [loader.started(at: 0), progressDelay.started(at: 0)],
      timeout: 1
    )

    XCTAssertTrue(store.isLive)
    XCTAssertFalse(store.showsProgress)

    loader.succeed(0, with: snapshot(solarPower: 8.4))
    await load.value

    XCTAssertTrue(store.isLive)
    XCTAssertFalse(store.showsProgress)
  }

  func testReplacementRejectsOlderProgressDelay() async {
    let loader = ControlledHomeEnergyLoader(requestCount: 2)
    let progressDelay = ControlledHomeEnergyDelay(delayCount: 2)
    let store = HomeAssistantHomeEnergyStore(
      loader: loader,
      progressSleep: { try? await progressDelay.sleep($0) }
    )
    let firstLoad = Task { await store.load() }
    await fulfillment(
      of: [loader.started(at: 0), progressDelay.started(at: 0)],
      timeout: 1
    )
    let secondLoad = Task { await store.load() }
    await fulfillment(
      of: [loader.started(at: 1), progressDelay.started(at: 1)],
      timeout: 1
    )

    progressDelay.finish(0)
    await fulfillment(of: [progressDelay.completed(at: 0)], timeout: 1)
    XCTAssertFalse(store.showsProgress)

    let progressShown = expectation(description: "Latest progress shown")
    let subscription = store.$showsProgress.dropFirst().sink { showsProgress in
      if showsProgress {
        progressShown.fulfill()
      }
    }
    progressDelay.finish(1)
    await fulfillment(of: [progressShown], timeout: 1)

    loader.succeed(1, with: snapshot(solarPower: 8.4))
    await secondLoad.value
    loader.succeed(0, with: snapshot(solarPower: 1.2))
    await firstLoad.value

    XCTAssertFalse(store.showsProgress)
    XCTAssertEqual(store.snapshot.pvPowerKilowatts, 8.4)
    withExtendedLifetime(subscription) {}
  }

  func testConnectionInvalidationClearsDelayedProgress() async {
    let loader = ControlledHomeEnergyLoader(requestCount: 1)
    let progressDelay = ControlledHomeEnergyDelay(delayCount: 1)
    let store = HomeAssistantHomeEnergyStore(
      loader: loader,
      progressSleep: { try? await progressDelay.sleep($0) }
    )
    let load = Task { await store.load() }
    await fulfillment(
      of: [loader.started(at: 0), progressDelay.started(at: 0)],
      timeout: 1
    )
    progressDelay.finish(0)
    let progressShown = expectation(description: "Progress shown")
    let subscription = store.$showsProgress.sink { showsProgress in
      if showsProgress {
        progressShown.fulfill()
      }
    }
    await fulfillment(of: [progressShown], timeout: 1)

    await store.synchronize(with: .requiresUserAction)

    XCTAssertFalse(store.showsProgress)
    XCTAssertFalse(store.isLoading)
    loader.succeed(0, with: snapshot(solarPower: 8.4))
    await load.value
    XCTAssertFalse(store.isLive)
    withExtendedLifetime(subscription) {}
  }

  func testConnectedStreamPublishesLaterValuesWithoutProgressFlicker() async {
    let loader = StreamingHomeEnergyLoader()
    let store = HomeAssistantHomeEnergyStore(loader: loader)
    let connection = Task {
      await store.synchronize(with: .ready(credentials))
    }
    await fulfillment(of: [loader.started], timeout: 1)
    let initialSnapshotPublished = expectation(description: "Initial energy snapshot published")
    let initialSubscription = store.$snapshot.dropFirst().sink { snapshot in
      if snapshot.pvPowerKilowatts == 2.1 {
        initialSnapshotPublished.fulfill()
      }
    }
    loader.yield(.live(snapshot(solarPower: 2.1)))
    await fulfillment(of: [initialSnapshotPublished], timeout: 1)
    XCTAssertFalse(store.showsProgress)

    let updatedSnapshotPublished = expectation(description: "Updated energy snapshot published")
    let updateSubscription = store.$snapshot.dropFirst()
      .filter { $0.pvPowerKilowatts == 9.1 }
      .prefix(1)
      .sink { _ in
        updatedSnapshotPublished.fulfill()
      }
    loader.yield(.live(snapshot(solarPower: 9.1)))
    await fulfillment(of: [updatedSnapshotPublished], timeout: 1)

    let reconnectingPublished = expectation(description: "Energy values marked stale")
    let reconnectingSubscription = store.$problem.compactMap(\.self).sink { problem in
      if problem == .reconnecting {
        reconnectingPublished.fulfill()
      }
    }
    loader.yield(.reconnecting(snapshot(solarPower: 9.1)))
    await fulfillment(of: [reconnectingPublished], timeout: 1)

    assertStale(store)

    let recovered = expectation(description: "Energy values live after reconnect")
    let recoverySubscription = store.$isLive.dropFirst().filter { $0 }.sink { _ in
      recovered.fulfill()
    }
    loader.yield(.live(snapshot(solarPower: 10.2)))
    await fulfillment(of: [recovered], timeout: 1)

    assertRecovered(store)
    connection.cancel()
    await connection.value
    withExtendedLifetime(
      (
        initialSubscription,
        updateSubscription,
        reconnectingSubscription,
        recoverySubscription
      )
    ) {}
  }

  private func snapshot(solarPower: Double) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: solarPower,
      batteryStateOfCharge: 76,
      homeConsumptionKilowatts: 3.1,
      gridPowerKilowatts: -2.7,
      generalPriceDollarsPerKilowattHour: 0.341,
      feedInPriceDollarsPerKilowattHour: 0.127
    )
  }

  private func assertRecovered(_ store: HomeAssistantHomeEnergyStore) {
    XCTAssertEqual(store.snapshot.pvPowerKilowatts, 10.2)
    XCTAssertTrue(store.isLive)
    XCTAssertNil(store.problem)
    XCTAssertFalse(store.showsProgress)
  }

  private func assertStale(_ store: HomeAssistantHomeEnergyStore) {
    XCTAssertEqual(store.snapshot.pvPowerKilowatts, 9.1)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.showsProgress)
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

private final class StreamingHomeEnergyLoader:
  HomeAssistantHomeEnergyLoading, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Home energy stream started")

  private let lock = NSLock()
  private var continuation: HomeAssistantHomeEnergyUpdateStream.Continuation?

  func homeEnergyUpdates() -> HomeAssistantHomeEnergyUpdateStream {
    HomeAssistantHomeEnergyUpdateStream { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }

  func yield(_ update: HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>) {
    let continuation = lock.withLock { self.continuation }
    continuation?.yield(update)
  }
}

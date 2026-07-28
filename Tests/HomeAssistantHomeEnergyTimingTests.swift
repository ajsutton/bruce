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
    await Task.yield()
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

    await store.synchronize(with: .unavailable)

    XCTAssertFalse(store.showsProgress)
    XCTAssertFalse(store.isLoading)
    loader.succeed(0, with: snapshot(solarPower: 8.4))
    await load.value
    XCTAssertFalse(store.isLive)
    withExtendedLifetime(subscription) {}
  }

  func testMonitorRefreshesImmediatelyAndManualLoadWins() async {
    let loader = ControlledHomeEnergyLoader(requestCount: 3)
    let refreshDelay = ControlledHomeEnergyDelay(delayCount: 1)
    let store = HomeAssistantHomeEnergyStore(
      loader: loader,
      refreshSleep: refreshDelay.sleep
    )
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    loader.succeed(0, with: snapshot(solarPower: 2.1))
    await connection.value

    let monitor = Task { await store.monitor() }
    await fulfillment(of: [loader.started(at: 1)], timeout: 1)
    let manualLoad = Task { await store.load() }
    await fulfillment(of: [loader.started(at: 2)], timeout: 1)

    loader.succeed(2, with: snapshot(solarPower: 9.1))
    await manualLoad.value
    loader.succeed(1, with: snapshot(solarPower: 3.2))
    await fulfillment(of: [refreshDelay.started(at: 0)], timeout: 1)

    XCTAssertEqual(store.snapshot.pvPowerKilowatts, 9.1)
    monitor.cancel()
    await monitor.value
  }

  func testMonitorDoesNotLoadWhileDisconnectedOrAlreadyLoading() async {
    let disconnectedLoader = ControlledHomeEnergyLoader(requestCount: 1)
    disconnectedLoader.started(at: 0).isInverted = true
    let disconnectedDelay = ControlledHomeEnergyDelay(delayCount: 1)
    let disconnectedStore = HomeAssistantHomeEnergyStore(
      loader: disconnectedLoader,
      refreshSleep: disconnectedDelay.sleep
    )
    let disconnectedMonitor = Task { await disconnectedStore.monitor() }
    await fulfillment(of: [disconnectedDelay.started(at: 0)], timeout: 1)
    await fulfillment(of: [disconnectedLoader.started(at: 0)], timeout: 0.1)
    disconnectedMonitor.cancel()
    await disconnectedMonitor.value

    let loadingLoader = ControlledHomeEnergyLoader(requestCount: 2)
    loadingLoader.started(at: 1).isInverted = true
    let loadingDelay = ControlledHomeEnergyDelay(delayCount: 1)
    let loadingStore = HomeAssistantHomeEnergyStore(
      loader: loadingLoader,
      refreshSleep: loadingDelay.sleep
    )
    let load = Task {
      await loadingStore.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [loadingLoader.started(at: 0)], timeout: 1)
    let loadingMonitor = Task { await loadingStore.monitor() }
    await fulfillment(of: [loadingDelay.started(at: 0)], timeout: 1)
    await fulfillment(of: [loadingLoader.started(at: 1)], timeout: 0.1)
    loadingMonitor.cancel()
    await loadingMonitor.value
    loadingLoader.succeed(0, with: snapshot(solarPower: 8.4))
    await load.value
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

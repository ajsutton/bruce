import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantRefreshPresentationTests: XCTestCase {
  func testOneShotChargerDefaultStreamPreservesSuccessfulValue() async {
    let store = HomeAssistantEVChargingStore(client: OneShotEVChargingClient())

    await store.synchronize(with: .connected(credentials))

    XCTAssertEqual(store.mode, .smart)
    XCTAssertTrue(store.isLive)
    XCTAssertNil(store.problem)
  }

  func testOneShotEnergyDefaultStreamPreservesSuccessfulValue() async {
    let store = HomeAssistantHomeEnergyStore(loader: OneShotEnergyLoader())

    await store.synchronize(with: .connected(credentials))

    XCTAssertEqual(store.snapshot.pvPowerKilowatts, 8.4)
    XCTAssertTrue(store.isLive)
    XCTAssertNil(store.problem)
  }

  func testTemperatureRefreshKeepsCachedReadingsWithoutClaimingTheyAreLive() async {
    let loader = RefreshingTemperatureLoader()
    let reading = HomeAssistantTemperatureReading(
      id: "climate.bedroom",
      name: "Bedroom",
      value: 22,
      targetValue: 23,
      unit: "°C",
      powerState: .poweredOn
    )
    let store = HomeAssistantTemperatureStore(loader: loader)
    let observation = Task { await store.load() }
    await fulfillment(of: [loader.started], timeout: 1)
    loader.yield(.live([reading]))
    await waitForValue(store.$isLive, matching: true)

    let refreshing = expectation(description: "Temperature refresh received")
    let subscription = store.$isRefreshing.dropFirst().filter { $0 }.sink { _ in
      refreshing.fulfill()
    }
    loader.yield(.refreshing([reading]))
    await fulfillment(of: [refreshing], timeout: 1)

    XCTAssertEqual(store.readings, [reading])
    XCTAssertFalse(store.isLive)
    XCTAssertTrue(store.isRefreshing)
    XCTAssertFalse(store.isLoading)
    XCTAssertNil(store.problem)
    observation.cancel()
    await observation.value
    withExtendedLifetime(subscription) {}
  }

  func testTemperatureRefreshPreservesLiveEmptyStateWithoutProgress() async {
    let loader = RefreshingTemperatureLoader()
    let store = HomeAssistantTemperatureStore(loader: loader)
    let observation = Task { await store.load() }
    await fulfillment(of: [loader.started], timeout: 1)
    loader.yield(.live([]))
    await waitForValue(store.$isLive, matching: true)

    loader.yield(.refreshing([]))
    await waitForValue(store.$isRefreshing, matching: true)

    XCTAssertTrue(store.readings.isEmpty)
    XCTAssertFalse(store.isLive)
    XCTAssertTrue(store.isRefreshing)
    XCTAssertFalse(store.isLoading)
    XCTAssertNil(store.problem)
    observation.cancel()
    await observation.value
  }

  func testTemperatureConsumerReplacementPreservesCachedReadings() async {
    let loader = ReplacingTemperatureLoader()
    let reading = HomeAssistantTemperatureReading(
      id: "climate.bedroom",
      name: "Bedroom",
      value: 22,
      targetValue: 23,
      unit: "°C",
      powerState: .poweredOn
    )
    let store = HomeAssistantTemperatureStore(loader: loader)
    let firstStarted = loader.expectSubscription(1)
    let firstObservation = Task { await store.load() }
    await fulfillment(of: [firstStarted], timeout: 1)
    loader.yield(.live([reading]), subscription: 1)
    await waitForValue(store.$isLive, matching: true)
    loader.yield(.refreshing([reading]), subscription: 1)
    await waitForValue(store.$isRefreshing, matching: true)
    firstObservation.cancel()
    await firstObservation.value

    let secondStarted = loader.expectSubscription(2)
    let secondObservation = Task { await store.load() }
    await fulfillment(of: [secondStarted], timeout: 1)
    let preserved = expectation(description: "Cached temperature reading preserved")
    let subscription = store.$readings.dropFirst().filter { $0 == [reading] }.sink { _ in
      preserved.fulfill()
    }
    loader.yield(.refreshing([]), subscription: 2)
    await fulfillment(of: [preserved], timeout: 1)

    XCTAssertEqual(store.readings, [reading])
    XCTAssertFalse(store.isLive)
    XCTAssertTrue(store.isRefreshing)
    XCTAssertFalse(store.isLoading)
    withExtendedLifetime(subscription) {}
    secondObservation.cancel()
    await secondObservation.value
  }

  func testEnergyRefreshKeepsCachedValuesWithoutClaimingTheyAreLive() async {
    let loader = RefreshingEnergyLoader()
    let snapshot = HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.4,
      batteryStateOfCharge: 76,
      homeConsumptionKilowatts: 3.1,
      gridPowerKilowatts: -2.7,
      generalPriceDollarsPerKilowattHour: 0.341,
      feedInPriceDollarsPerKilowattHour: 0.127
    )
    let store = HomeAssistantHomeEnergyStore(loader: loader)
    let observation = Task { await store.synchronize(with: .connected(credentials)) }
    await fulfillment(of: [loader.started], timeout: 1)
    loader.yield(.live(snapshot))
    await waitForValue(store.$isLive, matching: true)

    let refreshed = expectation(description: "Energy refresh received")
    let subscription = store.$isRefreshing.dropFirst().filter { $0 }.sink { _ in
      refreshed.fulfill()
    }
    loader.yield(.refreshing(snapshot))
    await fulfillment(of: [refreshed], timeout: 1)

    XCTAssertFalse(store.isLive)
    XCTAssertTrue(store.isRefreshing)
    XCTAssertFalse(store.isLoading)
    XCTAssertFalse(store.showsProgress)
    XCTAssertNil(store.problem)
    observation.cancel()
    await observation.value
    withExtendedLifetime(subscription) {}
  }

  func testChargerRefreshKeepsCachedStatusAndDisablesControls() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let observation = Task { await store.synchronize(with: .connected(credentials)) }
    await fulfillment(of: [client.started], timeout: 1)
    let snapshot = HomeAssistantEVChargingSnapshot(
      mode: .smart,
      activity: .connected,
      modeLastUpdated: Date(timeIntervalSince1970: 100)
    )
    client.yield(.live(snapshot))
    await waitForValue(store.$isLive, matching: true)

    let refreshed = expectation(description: "Charger refresh received")
    let subscription = store.$isRefreshing.dropFirst().filter { $0 }.sink { _ in
      refreshed.fulfill()
    }
    client.yield(.refreshing(snapshot))
    await fulfillment(of: [refreshed], timeout: 1)

    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.isActivityLive)
    XCTAssertTrue(store.isRefreshing)
    XCTAssertFalse(store.isLoading)
    XCTAssertFalse(store.canSelectMode)
    XCTAssertFalse(store.showsProgress)
    XCTAssertNil(store.problem)
    observation.cancel()
    await observation.value
    withExtendedLifetime(subscription) {}
  }

  private func waitForValue<P: Publisher>(
    _ publisher: P,
    matching expectedValue: P.Output
  ) async where P.Output: Equatable, P.Failure == Never {
    let published = expectation(description: "Expected refresh presentation value")
    let subscription = publisher.filter { $0 == expectedValue }.prefix(1).sink { _ in
      published.fulfill()
    }
    await fulfillment(of: [published], timeout: 1)
    withExtendedLifetime(subscription) {}
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

private struct OneShotEVChargingClient: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    .smart
  }

  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    .init(mode: .smart, activity: .connected)
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    mode
  }
}

private struct OneShotEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .init(
      pvPowerKilowatts: 8.4,
      batteryStateOfCharge: 76,
      homeConsumptionKilowatts: 3.1,
      gridPowerKilowatts: -2.7,
      generalPriceDollarsPerKilowattHour: 0.341,
      feedInPriceDollarsPerKilowattHour: 0.127
    )
  }
}

private final class ReplacingTemperatureLoader:
  HomeAssistantTemperatureLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var continuations:
    [Int: AsyncThrowingStream<HomeAssistantTemperatureUpdate, any Error>.Continuation] = [:]
  private var subscriptionCount = 0
  private var expectations: [Int: XCTestExpectation] = [:]

  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      let state = lock.withLock {
        subscriptionCount += 1
        continuations[subscriptionCount] = continuation
        return expectations.removeValue(forKey: subscriptionCount)
      }
      state?.fulfill()
    }
  }

  func expectSubscription(_ count: Int) -> XCTestExpectation {
    let expectation = XCTestExpectation(
      description: "Temperature subscription \(count) started"
    )
    let reached = lock.withLock {
      if subscriptionCount >= count { return true }
      expectations[count] = expectation
      return false
    }
    if reached { expectation.fulfill() }
    return expectation
  }

  func yield(_ update: HomeAssistantTemperatureUpdate, subscription: Int) {
    lock.withLock { continuations[subscription] }?.yield(update)
  }
}

private final class RefreshingTemperatureLoader:
  HomeAssistantTemperatureLoading, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Temperature refresh stream started")
  private let lock = NSLock()
  private var continuation:
    AsyncThrowingStream<HomeAssistantTemperatureUpdate, any Error>.Continuation?

  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      lock.withLock { self.continuation = continuation }
      started.fulfill()
    }
  }

  func yield(_ update: HomeAssistantTemperatureUpdate) {
    lock.withLock { continuation }?.yield(update)
  }
}

private final class RefreshingEnergyLoader:
  HomeAssistantHomeEnergyLoading, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Energy refresh stream started")
  private let lock = NSLock()
  private var continuation:
    AsyncThrowingStream<
      HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>, any Error
    >.Continuation?

  func homeEnergyUpdates() -> AsyncThrowingStream<
    HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>, any Error
  > {
    AsyncThrowingStream { continuation in
      lock.withLock { self.continuation = continuation }
      started.fulfill()
    }
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }

  func yield(_ update: HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>) {
    lock.withLock { continuation }?.yield(update)
  }
}

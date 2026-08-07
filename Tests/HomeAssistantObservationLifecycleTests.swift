import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantObservationLifecycleTests: XCTestCase {
  func testUpdatesRunUntilLastActiveWindowClosesAndResumeForReplacementWindow() async throws {
    let fixture = makeFixture()
    let firstSubscription = fixture.source.expectSubscriptionCount(1)
    let historiesReady = expectation(description: "Initial energy histories ready")
    let historySubscription = Publishers.CombineLatest3(
      fixture.energyStore.flowHistoryStore.$hasUsableHistory,
      fixture.energyStore.batteryHistoryStore.$hasUsableHistory,
      fixture.energyStore.priceHistoryStore.$hasUsableHistory
    )
    .filter { $0 && $1 && $2 }
    .prefix(1)
    .sink { _ in historiesReady.fulfill() }
    await fixture.coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSubscription, historiesReady], timeout: 1)

    let inactiveWindow = observationTask(fixture.coordinator, isActive: false)
    await fulfillment(of: [fixture.source.cancelled], timeout: 1)
    XCTAssertFalse(fixture.energyStore.isLive)
    assertHistoryIsStale(true, fixture: fixture)
    XCTAssertEqual(fixture.coordinator.serverStatus.phase, .updating)

    let secondSubscription = fixture.source.expectSubscriptionCount(2)
    let firstActiveWindow = observationTask(fixture.coordinator, isActive: true)
    await fulfillment(of: [secondSubscription], timeout: 1)
    XCTAssertEqual(fixture.historyLoader.requestCount, 3)
    let secondRegistered = expectation(description: "Second active window registered")
    let secondActiveWindow = observationTask(
      fixture.coordinator,
      isActive: true,
      registrationDidBegin: { secondRegistered.fulfill() }
    )
    await fulfillment(of: [secondRegistered], timeout: 1)
    inactiveWindow.cancel()
    await inactiveWindow.value
    firstActiveWindow.cancel()
    await firstActiveWindow.value

    try await yieldSolar(9.1, subscription: 2, fixture: fixture)
    assertHistoryIsStale(false, fixture: fixture)

    secondActiveWindow.cancel()
    await secondActiveWindow.value
    XCTAssertFalse(fixture.energyStore.isLive)
    XCTAssertEqual(fixture.energyStore.snapshot.pvPowerKilowatts, 9.1)

    let thirdSubscription = fixture.source.expectSubscriptionCount(3)
    let replacementWindow = observationTask(fixture.coordinator, isActive: true)
    await fulfillment(of: [thirdSubscription], timeout: 1)
    try await yieldSolar(9.4, subscription: 3, fixture: fixture)

    replacementWindow.cancel()
    await replacementWindow.value
    await fixture.coordinator.synchronize(with: .disconnected)
    withExtendedLifetime(historySubscription) {}
  }

  func testLongInactivityReloadsHistoryBeforeResuming() async {
    let start = Date(timeIntervalSince1970: 20_000)
    let dates = LifecycleDateSequence([
      start,
      start.addingTimeInterval(HomeEnergyHistorySampling.interval),
      start.addingTimeInterval(HomeEnergyHistorySampling.interval + 1),
    ])
    let fixture = makeFixture(now: dates.next)
    let firstSubscription = fixture.source.expectSubscriptionCount(1)
    let historiesReady = expectation(description: "Initial energy histories ready")
    let historySubscription = Publishers.CombineLatest3(
      fixture.energyStore.flowHistoryStore.$hasUsableHistory,
      fixture.energyStore.batteryHistoryStore.$hasUsableHistory,
      fixture.energyStore.priceHistoryStore.$hasUsableHistory
    )
    .filter { $0 && $1 && $2 }
    .prefix(1)
    .sink { _ in historiesReady.fulfill() }
    await fixture.coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSubscription, historiesReady], timeout: 1)

    let inactiveWindow = observationTask(fixture.coordinator, isActive: false)
    await fulfillment(of: [fixture.source.cancelled], timeout: 1)
    let historiesReloaded = fixture.historyLoader.expectRequestCount(6)
    let replacementWindow = observationTask(fixture.coordinator, isActive: true)
    await fulfillment(of: [historiesReloaded], timeout: 1)

    replacementWindow.cancel()
    inactiveWindow.cancel()
    await replacementWindow.value
    await inactiveWindow.value
    await fixture.coordinator.synchronize(with: .disconnected)
    withExtendedLifetime(historySubscription) {}
  }

  func testReplacementConnectionReloadsHistoryAfterShortInactivity() async {
    let start = Date(timeIntervalSince1970: 20_000)
    let dates = LifecycleDateSequence([
      start,
      start.addingTimeInterval(1),
      start.addingTimeInterval(2),
    ])
    let fixture = makeFixture(now: dates.next)
    let firstSubscription = fixture.source.expectSubscriptionCount(1)
    let historiesReady = fixture.historyLoader.expectRequestCount(3)
    await fixture.coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSubscription, historiesReady], timeout: 1)

    let inactiveWindow = observationTask(fixture.coordinator, isActive: false)
    await fulfillment(of: [fixture.source.cancelled], timeout: 1)
    await fixture.coordinator.synchronize(with: .connected(replacementCredentials))
    let historiesReloaded = fixture.historyLoader.expectRequestCount(6)
    let replacementWindow = observationTask(fixture.coordinator, isActive: true)
    await fulfillment(of: [historiesReloaded], timeout: 1)

    replacementWindow.cancel()
    inactiveWindow.cancel()
    await replacementWindow.value
    await inactiveWindow.value
    await fixture.coordinator.synchronize(with: .disconnected)
  }

  func testSuspensionCancelsBlockedHistoryRequests() async {
    let fixture = makeFixture(blocksHistoryRequests: true)
    let firstSubscription = fixture.source.expectSubscriptionCount(1)
    let historiesStarted = fixture.historyLoader.expectRequestCount(3)
    await fixture.coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSubscription, historiesStarted], timeout: 1)

    let historiesCancelled = fixture.historyLoader.expectCancellationCount(3)
    let inactiveWindow = observationTask(fixture.coordinator, isActive: false)
    await fulfillment(
      of: [fixture.source.cancelled, historiesCancelled],
      timeout: 1
    )

    inactiveWindow.cancel()
    await inactiveWindow.value
    await fixture.coordinator.synchronize(with: .disconnected)
  }

  func testShortInactivityReloadsHistoryThatWasAlreadyStale() async {
    let fixture = makeFixture()
    let firstSubscription = fixture.source.expectSubscriptionCount(1)
    let historiesReady = fixture.historyLoader.expectRequestCount(3)
    await fixture.coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSubscription, historiesReady], timeout: 1)
    fixture.energyStore.invalidateHistory()

    let inactiveWindow = observationTask(fixture.coordinator, isActive: false)
    await fulfillment(of: [fixture.source.cancelled], timeout: 1)
    let historiesReloaded = fixture.historyLoader.expectRequestCount(6)
    let replacementWindow = observationTask(fixture.coordinator, isActive: true)
    await fulfillment(of: [historiesReloaded], timeout: 1)

    replacementWindow.cancel()
    inactiveWindow.cancel()
    await replacementWindow.value
    await inactiveWindow.value
    await fixture.coordinator.synchronize(with: .disconnected)
  }

  func testDelayedLiveUpdateReloadsHistoryAfterQuickActivation() async throws {
    let clock = LifecycleClock(now: Date(timeIntervalSince1970: 20_000))
    let fixture = makeFixture(now: clock.callAsFunction)
    let firstSubscription = fixture.source.expectSubscriptionCount(1)
    let historiesReady = fixture.historyLoader.expectRequestCount(3)
    await fixture.coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSubscription, historiesReady], timeout: 1)

    let inactiveWindow = observationTask(fixture.coordinator, isActive: false)
    await fulfillment(of: [fixture.source.cancelled], timeout: 1)
    clock.advance(by: 1)
    let secondSubscription = fixture.source.expectSubscriptionCount(2)
    let replacementWindow = observationTask(fixture.coordinator, isActive: true)
    await fulfillment(of: [secondSubscription], timeout: 1)

    clock.advance(by: HomeEnergyHistorySampling.interval)
    let resumedTimestamp = clock()
    let historiesReloaded = fixture.historyLoader.expectRequestCount(6)
    let resumedSampleRetained = expectation(
      description: "Reloaded history retains the first resumed sample"
    )
    let historySubscription = fixture.energyStore.flowHistoryStore.$flowHistory
      .filter { history in
        history.readings.contains {
          $0.series == .pvGeneration
            && $0.timestamp == resumedTimestamp
            && $0.kilowatts == 9.1
        }
      }
      .prefix(1)
      .sink { _ in resumedSampleRetained.fulfill() }
    try await yieldSolar(9.1, subscription: 2, fixture: fixture)
    await fulfillment(of: [historiesReloaded, resumedSampleRetained], timeout: 1)

    replacementWindow.cancel()
    inactiveWindow.cancel()
    await replacementWindow.value
    await inactiveWindow.value
    await fixture.coordinator.synchronize(with: .disconnected)
    withExtendedLifetime(historySubscription) {}
  }

  func testExplicitRefreshAfterQuickResumePreservesHistoryReuse() async throws {
    let fixture = makeFixture()
    let firstSubscription = fixture.source.expectSubscriptionCount(1)
    let historiesReady = fixture.historyLoader.expectRequestCount(3)
    await fixture.coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSubscription, historiesReady], timeout: 1)
    try await yieldSolar(9.0, subscription: 1, fixture: fixture)

    let inactiveWindow = observationTask(fixture.coordinator, isActive: false)
    await fulfillment(of: [fixture.source.cancelled], timeout: 1)
    let secondSubscription = fixture.source.expectSubscriptionCount(2)
    let replacementWindow = observationTask(fixture.coordinator, isActive: true)
    await fulfillment(of: [secondSubscription], timeout: 1)

    let refreshedSubscription = fixture.source.expectSubscriptionCount(3)
    await fixture.coordinator.refresh()
    await fulfillment(of: [refreshedSubscription], timeout: 1)
    try await yieldSolar(9.1, subscription: 3, fixture: fixture)
    XCTAssertEqual(fixture.historyLoader.requestCount, 3)

    replacementWindow.cancel()
    inactiveWindow.cancel()
    await replacementWindow.value
    await inactiveWindow.value
    await fixture.coordinator.synchronize(with: .disconnected)
  }
}

extension HomeAssistantObservationLifecycleTests {
  private func observationTask(
    _ coordinator: HomeAssistantObservationCoordinator,
    isActive: Bool,
    registrationDidBegin: @MainActor @Sendable @escaping () -> Void = {}
  ) -> Task<Void, Never> {
    Task { @MainActor in
      await coordinator.observeUpdates(
        while: isActive,
        registrationDidBegin: registrationDidBegin
      )
    }
  }

  private func assertHistoryIsStale(
    _ expected: Bool,
    fixture: LifecycleFixture
  ) {
    XCTAssertEqual(fixture.energyStore.flowHistoryStore.isStale, expected)
    XCTAssertEqual(fixture.energyStore.batteryHistoryStore.isStale, expected)
    XCTAssertEqual(fixture.energyStore.priceHistoryStore.isStale, expected)
  }

  private func yieldSolar(
    _ solar: Double,
    subscription: Int,
    fixture: LifecycleFixture
  ) async throws {
    let received = expectation(description: "Energy update received")
    let subscriptionToken = fixture.energyStore.$snapshot
      .map(\.pvPowerKilowatts)
      .filter { $0 == solar }
      .prefix(1)
      .sink { _ in received.fulfill() }
    fixture.source.yield(
      .live(try states(solar: solar)),
      subscription: subscription
    )
    await fulfillment(of: [received], timeout: 1)
    withExtendedLifetime(subscriptionToken) {}
  }

  private func makeFixture(
    blocksHistoryRequests: Bool = false,
    now: @escaping @Sendable () -> Date = Date.init
  ) -> LifecycleFixture {
    let source = ControlledStateSource()
    let historyLoader = LifecycleHistoryLoader(
      blocksRequests: blocksHistoryRequests
    )
    source.started.assertForOverFulfill = false
    source.cancelled.assertForOverFulfill = false
    let states = HomeAssistantStateHub(source: source)
    let energyStore = HomeAssistantHomeEnergyStore(
      loader: HomeAssistantHomeEnergyStream(
        states: states,
        loader: historyLoader
      ),
      now: now
    )
    let coordinator = HomeAssistantObservationCoordinator(
      temperatureStore: HomeAssistantTemperatureStore(
        loader: LifecycleTemperatureLoader()
      ),
      chargingStore: HomeAssistantEVChargingStore(
        client: LifecycleChargingClient()
      ),
      garageDoorStore: HomeAssistantGarageDoorStore(
        loader: TestGarageDoorLoader()
      ),
      homeEnergyStore: energyStore,
      refreshStateFeed: { await states.refresh() },
      resetStateFeed: { await states.reset() },
      serverUpdates: { await states.stateUpdates() },
      now: now
    )
    return LifecycleFixture(
      source: source,
      historyLoader: historyLoader,
      energyStore: energyStore,
      coordinator: coordinator
    )
  }

  private func states(solar: Double) throws -> [HomeAssistantState] {
    let data = Data(
      """
      [
        {"entity_id":"sensor.sigen_plant_pv_power","state":"\(solar)","attributes":{}},
        {"entity_id":"sensor.sigen_plant_battery_state_of_charge","state":"76","attributes":{}},
        {"entity_id":"sensor.sigen_plant_consumed_power","state":"3.1","attributes":{}},
        {"entity_id":"sensor.sigen_plant_grid_active_power","state":"-2.7","attributes":{}},
        {"entity_id":"sensor.01krmdgkh60wyckeepvgtbbgv3_general_price","state":"0.341","attributes":{}},
        {"entity_id":"sensor.01krmdgkh60wyckeepvgtbbgv3_feed_in_price","state":"0.127","attributes":{}}
      ]
      """.utf8
    )
    return try JSONDecoder().decode([HomeAssistantState].self, from: data)
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

@MainActor
private struct LifecycleFixture {
  let source: ControlledStateSource
  let historyLoader: LifecycleHistoryLoader
  let energyStore: HomeAssistantHomeEnergyStore
  let coordinator: HomeAssistantObservationCoordinator
}

private struct LifecycleTemperatureLoader: HomeAssistantTemperatureLoading {
  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { _ in }
  }
}

private struct LifecycleChargingClient: HomeAssistantEVCharging {
  let providesContinuousUpdates = true

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode { .smart }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    mode
  }

  func evChargingUpdates() -> HomeAssistantEVChargingUpdateStream {
    HomeAssistantEVChargingUpdateStream { _ in }
  }
}

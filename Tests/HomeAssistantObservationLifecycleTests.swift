import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantObservationLifecycleTests: XCTestCase {
  func testUpdatesRunUntilLastActiveWindowClosesAndResumeForReplacementWindow() async throws {
    let fixture = makeFixture()
    let firstSubscription = fixture.source.expectSubscriptionCount(1)
    await fixture.coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSubscription], timeout: 1)

    let inactiveWindow = observationTask(fixture.coordinator, isActive: false)
    await fulfillment(of: [fixture.source.cancelled], timeout: 1)
    XCTAssertFalse(fixture.energyStore.isLive)
    XCTAssertEqual(fixture.coordinator.serverStatus.phase, .updating)

    let secondSubscription = fixture.source.expectSubscriptionCount(2)
    let firstActiveWindow = observationTask(fixture.coordinator, isActive: true)
    await fulfillment(of: [secondSubscription], timeout: 1)
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
  }

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

  private func makeFixture() -> LifecycleFixture {
    let source = ControlledStateSource()
    source.started.assertForOverFulfill = false
    source.cancelled.assertForOverFulfill = false
    let states = HomeAssistantStateHub(source: source)
    let energyStore = HomeAssistantHomeEnergyStore(
      loader: HomeAssistantHomeEnergyStream(
        states: states,
        loader: UnusedLifecycleEnergyLoader()
      )
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
      serverUpdates: { await states.stateUpdates() }
    )
    return LifecycleFixture(
      source: source,
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
}

@MainActor
private struct LifecycleFixture {
  let source: ControlledStateSource
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

private struct UnusedLifecycleEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }
}

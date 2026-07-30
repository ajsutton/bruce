import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantObservationCoordinatorTests: XCTestCase {
  func testRefreshKeepsConsumersAttachedAndPreservesCachedPresentation() async throws {
    let fixture = makeRefreshFixture()
    let source = fixture.source
    let chargingStore = fixture.chargingStore
    let homeEnergyStore = fixture.homeEnergyStore
    let temperatureStore = fixture.temperatureStore
    let coordinator = fixture.coordinator
    let firstSource = source.expectSubscriptionCount(1)
    await coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSource], timeout: 1)
    source.yield(.live(try coordinatorStates(power: 0, solar: 8.4)))
    await waitForValue(chargingStore.$isLive, matching: true)
    await waitForValue(homeEnergyStore.$isLive, matching: true)
    await waitForValue(temperatureStore.$isLive, matching: true)

    let secondSource = source.expectSubscriptionCount(2)
    await coordinator.refresh()
    await waitForRefreshing(chargingStore, homeEnergyStore, temperatureStore)
    await fulfillment(of: [secondSource], timeout: 1)

    assertCachedPresentation(
      chargingStore: chargingStore,
      homeEnergyStore: homeEnergyStore,
      temperatureStore: temperatureStore
    )
    source.yield(
      .live(try coordinatorStates(power: 7_024, solar: 9.1, mode: "On")),
      subscription: 2
    )
    await waitForValue(chargingStore.$mode.compactMap(\.self), matching: .charging)
    await waitForValue(homeEnergyStore.$isLive, matching: true)
    await waitForValue(temperatureStore.$isLive, matching: true)

    assertFreshPresentation(
      homeEnergyStore: homeEnergyStore,
      temperatureStore: temperatureStore,
      source: source
    )
    await coordinator.synchronize(with: .disconnected)
  }

  private func makeRefreshFixture() -> CoordinatorRefreshFixture {
    let source = ControlledStateSource()
    source.started.assertForOverFulfill = false
    source.cancelled.assertForOverFulfill = false
    let states = HomeAssistantStateHub(source: source)
    let chargingStore = HomeAssistantEVChargingStore(
      client: HomeAssistantEVChargingStream(
        states: states,
        controller: UnusedCoordinatorEVChargingController()
      )
    )
    let homeEnergyStore = HomeAssistantHomeEnergyStore(
      loader: HomeAssistantHomeEnergyStream(
        states: states,
        loader: UnusedCoordinatorEnergyLoader()
      )
    )
    let temperatureStore = HomeAssistantTemperatureStore(
      loader: CoordinatorStateTemperatureLoader(states: states)
    )
    let coordinator = HomeAssistantObservationCoordinator(
      temperatureStore: temperatureStore,
      chargingStore: chargingStore,
      garageDoorStore: HomeAssistantGarageDoorStore(
        loader: TestGarageDoorLoader()
      ),
      homeEnergyStore: homeEnergyStore,
      refreshStateFeed: { await states.refresh() },
      serverUpdates: { await states.stateUpdates() }
    )
    return CoordinatorRefreshFixture(
      source: source,
      chargingStore: chargingStore,
      homeEnergyStore: homeEnergyStore,
      temperatureStore: temperatureStore,
      coordinator: coordinator
    )
  }

  func testServerStatusRecoversAfterTerminalFeedFailure() async throws {
    let fixture = makeRefreshFixture()
    let firstSource = fixture.source.expectSubscriptionCount(1)
    await fixture.coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSource], timeout: 1)
    fixture.source.yield(.live(try coordinatorStates(power: 0, solar: 8.4)))
    await waitForValue(fixture.coordinator.$serverStatus.map(\.phase), matching: .live)

    fixture.source.finish(throwing: URLError(.networkConnectionLost), subscription: 1)
    await waitForValue(fixture.coordinator.$serverStatus.map(\.phase), matching: .unavailable)
    let secondSource = fixture.source.expectSubscriptionCount(2)

    await fixture.coordinator.refresh()
    await fulfillment(of: [secondSource], timeout: 1)
    fixture.source.yield(
      .live(try coordinatorStates(power: 0, solar: 9.1)),
      subscription: 2
    )

    await waitForValue(fixture.coordinator.$serverStatus.map(\.phase), matching: .live)
    await fixture.coordinator.synchronize(with: .disconnected)
  }

  func testServerStatusRecoversAfterFeedCompletes() async throws {
    let fixture = makeRefreshFixture()
    let firstSource = fixture.source.expectSubscriptionCount(1)
    await fixture.coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSource], timeout: 1)
    fixture.source.yield(.live(try coordinatorStates(power: 0, solar: 8.4)))
    await waitForValue(fixture.coordinator.$serverStatus.map(\.phase), matching: .live)

    fixture.source.finish(subscription: 1)
    await waitForValue(fixture.coordinator.$serverStatus.map(\.phase), matching: .unavailable)
    let secondSource = fixture.source.expectSubscriptionCount(2)

    await fixture.coordinator.refresh()
    await fulfillment(of: [secondSource], timeout: 1)
    fixture.source.yield(
      .live(try coordinatorStates(power: 0, solar: 9.1)),
      subscription: 2
    )

    await waitForValue(fixture.coordinator.$serverStatus.map(\.phase), matching: .live)
    await fixture.coordinator.synchronize(with: .disconnected)
  }

  func testCancellingNewestSceneCallerDoesNotStopAppLifetimeObservation() async {
    let client = StreamingEVChargingClient()
    let chargingStore = HomeAssistantEVChargingStore(client: client)
    let coordinator = HomeAssistantObservationCoordinator(
      temperatureStore: HomeAssistantTemperatureStore(
        loader: CoordinatorTemperatureLoader()
      ),
      chargingStore: chargingStore,
      garageDoorStore: HomeAssistantGarageDoorStore(
        loader: TestGarageDoorLoader()
      ),
      homeEnergyStore: HomeAssistantHomeEnergyStore(
        loader: CoordinatorEnergyLoader()
      )
    )
    await coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [client.started], timeout: 1)

    let firstSceneCaller = Task {
      await coordinator.synchronize(with: .connected(credentials))
    }
    let newestSceneCaller = Task {
      await coordinator.synchronize(with: .connected(credentials))
    }
    newestSceneCaller.cancel()
    await firstSceneCaller.value
    await newestSceneCaller.value

    let live = expectation(description: "App-lifetime observer remained active")
    let subscription = chargingStore.$isLive.filter { $0 }.prefix(1).sink { _ in
      live.fulfill()
    }
    client.yield(.live(.init(mode: .smart, activity: .connected)))
    await fulfillment(of: [live], timeout: 1)

    XCTAssertEqual(chargingStore.mode, .smart)
    XCTAssertTrue(chargingStore.isLive)
    await coordinator.synchronize(with: .disconnected)
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

  private func waitForValue<P: Publisher>(
    _ publisher: P,
    matching expectedValue: P.Output
  ) async where P.Output: Equatable, P.Failure == Never {
    let published = expectation(description: "Expected coordinator value")
    let subscription = publisher.filter { $0 == expectedValue }.prefix(1).sink { _ in
      published.fulfill()
    }
    await fulfillment(of: [published], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  private func assertCachedPresentation(
    chargingStore: HomeAssistantEVChargingStore,
    homeEnergyStore: HomeAssistantHomeEnergyStore,
    temperatureStore: HomeAssistantTemperatureStore
  ) {
    XCTAssertEqual(chargingStore.mode, .smart)
    XCTAssertEqual(homeEnergyStore.snapshot.pvPowerKilowatts, 8.4)
    XCTAssertEqual(temperatureStore.readings.first?.value, 8.4)
    XCTAssertFalse(chargingStore.isLoading)
    XCTAssertFalse(homeEnergyStore.isLoading)
    XCTAssertFalse(temperatureStore.isLoading)
  }

  private func waitForRefreshing(
    _ chargingStore: HomeAssistantEVChargingStore,
    _ homeEnergyStore: HomeAssistantHomeEnergyStore,
    _ temperatureStore: HomeAssistantTemperatureStore
  ) async {
    await waitForValue(chargingStore.$isRefreshing, matching: true)
    await waitForValue(homeEnergyStore.$isRefreshing, matching: true)
    await waitForValue(temperatureStore.$isRefreshing, matching: true)
  }

  private func assertFreshPresentation(
    homeEnergyStore: HomeAssistantHomeEnergyStore,
    temperatureStore: HomeAssistantTemperatureStore,
    source: ControlledStateSource
  ) {
    XCTAssertEqual(homeEnergyStore.snapshot.pvPowerKilowatts, 9.1)
    XCTAssertEqual(temperatureStore.readings.first?.value, 9.1)
    XCTAssertEqual(source.subscriptionCount, 2)
  }

  private func coordinatorStates(
    power: Double,
    solar: Double,
    mode: String = "Smart Charging"
  ) throws -> [HomeAssistantState] {
    let data = Data(
      """
      [
        {"entity_id":"input_select.ev_charging_mode","state":"\(mode)","attributes":{"options":["Off","Smart Charging","On"]},"last_updated":"2026-07-28T01:02:03Z"},
        {"entity_id":"sensor.home_myenergi_home_power_charging","state":"\(power)","attributes":{"device_class":"power","unit_of_measurement":"W"}},
        {"entity_id":"sensor.zappi_myenergi_zappi_26482259_plug_status","state":"EV Connected","attributes":{}},
        {"entity_id":"sensor.zappi_myenergi_zappi_26482259_status","state":"Ready","attributes":{}},
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
}

extension HomeAssistantObservationCoordinatorTests {
  func testRefreshRestartsObserversWhenSharedFeedIsInactive() async {
    let client = StreamingEVChargingClient()
    client.started.assertForOverFulfill = false
    let chargingStore = HomeAssistantEVChargingStore(client: client)
    let coordinator = HomeAssistantObservationCoordinator(
      temperatureStore: HomeAssistantTemperatureStore(
        loader: CoordinatorTemperatureLoader()
      ),
      chargingStore: chargingStore,
      garageDoorStore: HomeAssistantGarageDoorStore(
        loader: TestGarageDoorLoader()
      ),
      homeEnergyStore: HomeAssistantHomeEnergyStore(
        loader: CoordinatorEnergyLoader()
      )
    )
    await coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [client.started], timeout: 1)
    client.finishUpdates()
    await waitForValue(
      chargingStore.$problem.compactMap(\.self),
      matching: .connectionUnavailable
    )

    let restarted = client.expectNextStreamStart()
    await coordinator.refresh()
    await fulfillment(of: [restarted], timeout: 1)

    await coordinator.synchronize(with: .disconnected)
  }
}

@MainActor
private struct CoordinatorRefreshFixture {
  let source: ControlledStateSource
  let chargingStore: HomeAssistantEVChargingStore
  let homeEnergyStore: HomeAssistantHomeEnergyStore
  let temperatureStore: HomeAssistantTemperatureStore
  let coordinator: HomeAssistantObservationCoordinator
}

private struct CoordinatorTemperatureLoader: HomeAssistantTemperatureLoading {
  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      continuation.yield(.live([]))
    }
  }
}

private struct CoordinatorEnergyLoader: HomeAssistantHomeEnergyLoading {
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

private struct CoordinatorStateTemperatureLoader: HomeAssistantTemperatureLoading {
  let states: any HomeAssistantStateLoading

  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await update in await states.stateUpdates() {
            let readings = update.states.compactMap(Self.reading)
            switch update.phase {
            case .live: continuation.yield(.live(readings))
            case .refreshing: continuation.yield(.refreshing(readings))
            case .reconnecting: continuation.yield(.reconnecting(readings))
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private static func reading(
    from state: HomeAssistantState
  ) -> HomeAssistantTemperatureReading? {
    guard state.entityID == "sensor.sigen_plant_pv_power",
      let value = Double(state.state)
    else {
      return nil
    }
    return HomeAssistantTemperatureReading(
      id: state.entityID,
      name: "Test temperature",
      value: value,
      targetValue: nil,
      unit: "°C",
      powerState: .unavailable
    )
  }
}

private struct UnusedCoordinatorEVChargingController: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw CoordinatorTestError.unexpectedRequest
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    throw CoordinatorTestError.unexpectedRequest
  }
}

private struct UnusedCoordinatorEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw CoordinatorTestError.unexpectedRequest
  }
}

private enum CoordinatorTestError: Error {
  case unexpectedRequest
}

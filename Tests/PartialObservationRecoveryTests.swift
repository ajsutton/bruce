import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class PartialObservationRecoveryTests: XCTestCase {
  func testRefreshRestartsOnlyFailedTemperatureObserver() async throws {
    let source = ControlledStateSource()
    source.started.assertForOverFulfill = false
    source.cancelled.assertForOverFulfill = false
    let states = HomeAssistantStateHub(source: source)
    let temperatureLoader = RecoverableCoordinatorTemperatureLoader(states: states)
    let temperatureStore = HomeAssistantTemperatureStore(loader: temperatureLoader)
    let chargingStore = HomeAssistantEVChargingStore(
      client: HomeAssistantEVChargingStream(
        states: states,
        controller: PartialRecoveryEVChargingController()
      )
    )
    let homeEnergyStore = HomeAssistantHomeEnergyStore(
      loader: HomeAssistantHomeEnergyStream(
        states: states,
        loader: PartialRecoveryEnergyLoader()
      )
    )
    let coordinator = HomeAssistantObservationCoordinator(
      temperatureStore: temperatureStore,
      chargingStore: chargingStore,
      garageDoorStore: HomeAssistantGarageDoorStore(loader: TestGarageDoorLoader()),
      homeEnergyStore: homeEnergyStore,
      refreshStateFeed: { await states.refresh() }
    )
    let firstSource = source.expectSubscriptionCount(1)
    await coordinator.synchronize(with: .connected(credentials))
    await fulfillment(of: [firstSource, temperatureLoader.started], timeout: 1)
    source.yield(.live(try statesFixture(solar: 8.4)))
    await waitForValue(temperatureStore.$isLive, matching: true)
    await waitForValue(chargingStore.$isLive, matching: true)
    await waitForValue(homeEnergyStore.$isLive, matching: true)

    temperatureLoader.failFirstObservation()
    await waitForValue(temperatureStore.$problem.compactMap(\.self), matching: .other)
    let restartedTemperature = temperatureLoader.expectSubscriptionCount(2)
    let secondSource = source.expectSubscriptionCount(2)
    await coordinator.refresh()
    await fulfillment(of: [restartedTemperature, secondSource], timeout: 1)
    await waitForValue(temperatureStore.$isRefreshing, matching: true)

    XCTAssertTrue(chargingStore.isRefreshing)
    XCTAssertTrue(homeEnergyStore.isRefreshing)
    XCTAssertFalse(chargingStore.isLoading || homeEnergyStore.isLoading)
    XCTAssertEqual(chargingStore.mode, .smart)
    XCTAssertEqual(homeEnergyStore.snapshot.pvPowerKilowatts, 8.4)
    source.yield(.live(try statesFixture(solar: 9.1)), subscription: 2)
    await waitForValue(temperatureStore.$isLive, matching: true)

    XCTAssertEqual(temperatureStore.readings.first?.value, 9.1)
    XCTAssertTrue(chargingStore.isLive && homeEnergyStore.isLive)
    XCTAssertEqual(source.subscriptionCount, 2)
    await coordinator.synchronize(with: .disconnected)
  }

  private func waitForValue<P: Publisher>(
    _ publisher: P,
    matching expectedValue: P.Output
  ) async where P.Output: Equatable, P.Failure == Never {
    let published = expectation(description: "Expected partial recovery value")
    let subscription = publisher.filter { $0 == expectedValue }.prefix(1).sink { _ in
      published.fulfill()
    }
    await fulfillment(of: [published], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  private func statesFixture(solar: Double) throws -> [HomeAssistantState] {
    let data = Data(
      """
      [
        {"entity_id":"input_select.ev_charging_mode","state":"Smart Charging","attributes":{"options":["Off","Smart Charging","On"]},"last_updated":"2026-07-28T01:02:03Z"},
        {"entity_id":"sensor.home_myenergi_home_power_charging","state":"0","attributes":{"device_class":"power","unit_of_measurement":"W"}},
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

private final class RecoverableCoordinatorTemperatureLoader:
  HomeAssistantTemperatureLoading, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Temperature observer started")
  private let states: any HomeAssistantStateLoading
  private let lock = NSLock()
  private var subscriptionCount = 0
  private var failedContinuation:
    AsyncThrowingStream<HomeAssistantTemperatureUpdate, any Error>.Continuation?
  private var nextSubscriptionExpectation: XCTestExpectation?

  init(states: any HomeAssistantStateLoading) {
    self.states = states
  }

  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      let nextExpectation = lock.withLock {
        subscriptionCount += 1
        if subscriptionCount == 1 {
          failedContinuation = continuation
        }
        let expectation = nextSubscriptionExpectation
        nextSubscriptionExpectation = nil
        return expectation
      }
      started.fulfill()
      nextExpectation?.fulfill()
      let task = Task { [states] in
        do {
          for try await update in await states.stateUpdates() {
            continuation.yield(Self.temperatureUpdate(update))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func failFirstObservation() {
    let continuation = lock.withLock {
      let continuation = failedContinuation
      failedContinuation = nil
      return continuation
    }
    continuation?.finish(throwing: PartialRecoveryError.contextFailed)
  }

  func expectSubscriptionCount(_ count: Int) -> XCTestExpectation {
    let expectation = XCTestExpectation(
      description: "Temperature subscription \(count) started"
    )
    lock.withLock {
      nextSubscriptionExpectation = expectation
    }
    return expectation
  }

  private static func temperatureUpdate(
    _ update: HomeAssistantStateUpdate
  ) -> HomeAssistantTemperatureUpdate {
    let readings = update.states.compactMap { state -> HomeAssistantTemperatureReading? in
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
    switch update.phase {
    case .live: return .live(readings)
    case .refreshing: return .refreshing(readings)
    case .reconnecting: return .reconnecting(readings)
    }
  }
}

private struct PartialRecoveryEVChargingController: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw PartialRecoveryError.unexpectedRequest
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    throw PartialRecoveryError.unexpectedRequest
  }
}

private struct PartialRecoveryEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw PartialRecoveryError.unexpectedRequest
  }
}

private enum PartialRecoveryError: Error {
  case contextFailed
  case unexpectedRequest
}

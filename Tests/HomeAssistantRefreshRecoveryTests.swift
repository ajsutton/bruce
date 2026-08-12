import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantRefreshRecoveryTests: XCTestCase {
  func testSuccessfulManualCheckRecoversAfterTerminalFeedFailure() async throws {
    let source = ControlledStateSource()
    source.started.assertForOverFulfill = false
    let states = HomeAssistantStateHub(source: source)
    let fixture = recoveryFixture(states: states)
    let coordinator = fixture.coordinator
    let firstSource = source.expectSubscriptionCount(1)
    await coordinator.synchronize(with: .ready(credentials))
    await fulfillment(of: [firstSource], timeout: 1)
    source.yield(.live(try chargingStates(power: 0)))
    await waitForValue(coordinator.$serverStatus.map(\.phase), matching: .live)
    source.finish(throwing: URLError(.networkConnectionLost), subscription: 1)
    await waitForValue(coordinator.$serverStatus.map(\.phase), matching: .unavailable)
    let secondSource = source.expectSubscriptionCount(2)
    let setupStore = HomeAssistantSetupStore(
      discovery: EmptyRefreshRecoveryDiscovery(),
      connection: SuccessfulRefreshRecoveryConnection(credentials: credentials)
    )
    setupStore.setConnectionCheckDidSucceed { await coordinator.refresh() }
    await setupStore.restoreSavedConnection()

    setupStore.testConnection()
    await fulfillment(of: [secondSource], timeout: 1)
    source.yield(.live(try chargingStates(power: 9.1)), subscription: 2)

    await waitForValue(coordinator.$serverStatus.map(\.phase), matching: .live)
    await waitForValue(fixture.temperatureStore.$readings.map(\.first?.value), matching: 9.1)
    XCTAssertTrue(fixture.temperatureStore.isLive)
    XCTAssertEqual(setupStore.connectionCheckState, .succeeded)
    await coordinator.synchronize(with: .signedOut)
  }

  func testUnchangedModeRefreshClearsUpdateError() async throws {
    let source = ControlledStateSource()
    source.started.assertForOverFulfill = false
    source.cancelled.assertForOverFulfill = false
    let states = HomeAssistantStateHub(source: source)
    let store = HomeAssistantEVChargingStore(
      client: HomeAssistantEVChargingStream(
        states: states,
        controller: FailingModeController()
      )
    )
    let observation = Task {
      await store.synchronize(with: .ready(credentials))
    }
    await fulfillment(of: [source.started], timeout: 1)
    let liveStates = try chargingStates()
    source.yield(.live(liveStates))
    await waitForValue(store.$isLive, matching: true)

    await store.selectMode(.charging)
    XCTAssertEqual(store.problem, .updateFailed)

    let replacementStarted = source.expectSubscriptionCount(2)
    let refreshedActiveFeed = await states.refresh()
    XCTAssertTrue(refreshedActiveFeed)
    await waitForValue(store.$problem, matching: nil)
    await fulfillment(of: [replacementStarted], timeout: 1)
    source.yield(.live(liveStates))
    await waitForValue(store.$isLive, matching: true)

    XCTAssertEqual(store.mode, .smart)
    XCTAssertTrue(store.isLive)
    observation.cancel()
    await observation.value
  }

  private func waitForValue<P: Publisher>(
    _ publisher: P,
    matching expectedValue: P.Output
  ) async where P.Output: Equatable, P.Failure == Never {
    let published = expectation(description: "Expected refreshed store value")
    let subscription = publisher.filter { $0 == expectedValue }.prefix(1).sink { _ in
      published.fulfill()
    }
    await fulfillment(of: [published], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  private func recoveryFixture(
    states: HomeAssistantStateHub
  ) -> RefreshRecoveryFixture {
    let temperatureStore = HomeAssistantTemperatureStore(
      loader: RefreshRecoveryTemperatureLoader(states: states)
    )
    let coordinator = HomeAssistantObservationCoordinator(
      temperatureStore: temperatureStore,
      chargingStore: HomeAssistantEVChargingStore(client: RefreshRecoveryChargingClient()),
      garageDoorStore: HomeAssistantGarageDoorStore(loader: TestGarageDoorLoader()),
      homeEnergyStore: HomeAssistantHomeEnergyStore(loader: RefreshRecoveryEnergyLoader()),
      refreshStateFeed: { await states.refresh() },
      serverUpdates: { await states.stateUpdates() }
    )
    return RefreshRecoveryFixture(
      coordinator: coordinator,
      temperatureStore: temperatureStore
    )
  }

  private func chargingStates(power: Double = 0) throws -> [HomeAssistantState] {
    let data = Data(
      """
      [
        {
          "entity_id": "input_select.ev_charging_mode",
          "state": "Smart Charging",
          "attributes": {
            "options": ["Off", "Smart Charging", "On"]
          },
          "last_updated": "2026-07-27T01:02:03Z"
        },
        {
          "entity_id": "sensor.home_myenergi_home_power_charging",
          "state": "\(power)",
          "attributes": {
            "device_class": "power",
            "unit_of_measurement": "W"
          },
          "last_updated": "2026-07-27T01:02:03Z"
        },
        {
          "entity_id": "sensor.zappi_myenergi_zappi_26482259_plug_status",
          "state": "EV Connected",
          "attributes": {},
          "last_updated": "2026-07-27T01:02:03Z"
        },
        {
          "entity_id": "sensor.zappi_myenergi_zappi_26482259_status",
          "state": "Ready",
          "attributes": {},
          "last_updated": "2026-07-27T01:02:03Z"
        }
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

private struct FailingModeController: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw HomeAssistantAPIError.invalidResponse
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    throw HomeAssistantAPIError.server(statusCode: 500)
  }
}

private struct EmptyRefreshRecoveryDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { $0.finish() }
  }
}

@MainActor
private final class SuccessfulRefreshRecoveryConnection: HomeAssistantConnecting {
  private let credentials: HomeAssistantCredentials

  init(credentials: HomeAssistantCredentials) {
    self.credentials = credentials
  }

  func connect(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    credentials
  }

  func restore() async throws -> HomeAssistantCredentials? { credentials }
  func testConnection() async throws -> HomeAssistantCredentials { credentials }
  func disconnect() async throws {}
  func cancel() {}
}

private struct RefreshRecoveryTemperatureLoader: HomeAssistantTemperatureLoading {
  let states: any HomeAssistantStateLoading

  func temperatureUpdates() -> AsyncThrowingStream<HomeAssistantTemperatureUpdate, any Error> {
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
    guard state.entityID == "sensor.home_myenergi_home_power_charging",
      let value = Double(state.state)
    else { return nil }
    return HomeAssistantTemperatureReading(
      id: state.entityID,
      name: "Test value",
      value: value,
      targetValue: nil,
      unit: "W",
      powerState: .unavailable
    )
  }
}

@MainActor
private struct RefreshRecoveryFixture {
  let coordinator: HomeAssistantObservationCoordinator
  let temperatureStore: HomeAssistantTemperatureStore
}

private struct RefreshRecoveryChargingClient: HomeAssistantEVCharging {
  let providesContinuousUpdates = true

  func evChargingUpdates() -> HomeAssistantEVChargingUpdateStream {
    HomeAssistantEVChargingUpdateStream { _ in }
  }

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode { .smart }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode { mode }
}

private struct RefreshRecoveryEnergyLoader: HomeAssistantHomeEnergyLoading {
  let providesContinuousEnergyUpdates = true

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot { .unavailable }

  func homeEnergyUpdates() -> HomeAssistantHomeEnergyUpdateStream {
    HomeAssistantHomeEnergyUpdateStream { _ in }
  }
}

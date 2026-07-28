import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantRefreshRecoveryTests: XCTestCase {
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
      await store.synchronize(with: .connected(credentials))
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

  private func chargingStates() throws -> [HomeAssistantState] {
    let data = Data(
      """
      [
        {
          "entity_id": "input_select.ev_charging_mode",
          "state": "Smart Charging",
          "attributes": {},
          "last_updated": "2026-07-27T01:02:03Z"
        },
        {
          "entity_id": "sensor.home_myenergi_home_power_charging",
          "state": "0",
          "attributes": {},
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

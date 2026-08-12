import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantEVChargingDiscoveryTests: XCTestCase {
  func testAbsentUpdateCompletesDiscoveryWithoutAnError() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .ready(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)

    client.yield(.absent)
    await waitForValue(store.$isLoading, matching: false)

    XCTAssertTrue(store.hasCompletedDiscovery)
    XCTAssertNil(store.mode)
    XCTAssertNil(store.problem)
    connection.cancel()
    await connection.value
  }

  func testAmbiguousLiveSelectorsSurfaceAnErrorInsteadOfAbsence() async throws {
    let source = ControlledStateSource()
    let store = HomeAssistantEVChargingStore(
      client: HomeAssistantEVChargingStream(
        states: source,
        controller: UnusedDiscoveryController()
      )
    )
    let connection = Task {
      await store.synchronize(with: .ready(credentials))
    }
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(.live(try ambiguousSelectorStates()))
    await waitForValue(store.$problem, matching: .invalidResponse)

    XCTAssertFalse(store.hasCompletedDiscovery)
    XCTAssertNil(store.mode)
    connection.cancel()
    await connection.value
  }

  func testAbsentUpdateInvalidatesModeChangeBeforeLateSuccess() async {
    await assertAbsenceWinsModeChange { $0.succeedSet(with: .charging) }
  }

  func testAbsentUpdateInvalidatesModeChangeBeforeLateFailure() async {
    await assertAbsenceWinsModeChange { $0.failSet() }
  }

  private func assertAbsenceWinsModeChange(
    complete: (StreamingEVChargingClient) -> Void
  ) async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .ready(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$mode, matching: .off)

    let change = Task { await store.selectMode(.charging) }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(.absent)
    await waitForValue(store.$isChanging, matching: false)
    complete(client)
    await change.value

    XCTAssertNil(store.mode)
    XCTAssertTrue(store.hasCompletedDiscovery)
    XCTAssertNil(store.problem)
    connection.cancel()
    await connection.value
  }

  private func ambiguousSelectorStates() throws -> [HomeAssistantState] {
    try JSONDecoder().decode(
      [HomeAssistantState].self,
      from: Data(
        """
        [
          {
            "entity_id": "input_select.ev_charging_mode",
            "state": "Smart Charging",
            "attributes": {"options": ["Off", "Smart Charging", "On"]}
          },
          {
            "entity_id": "input_select.garage_car_charging",
            "state": "Smart Charging",
            "attributes": {"options": ["Off", "Smart Charging", "On"]}
          }
        ]
        """.utf8
      )
    )
  }

  private func waitForValue<P: Publisher>(
    _ publisher: P,
    matching expectedValue: P.Output
  ) async where P.Output: Equatable, P.Failure == Never {
    let published = expectation(description: "Expected published value")
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

private struct UnusedDiscoveryController: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw HomeAssistantAPIError.invalidResponse
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    throw HomeAssistantAPIError.invalidResponse
  }
}

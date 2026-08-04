import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class EVChargingSnapshotOrderingTests: XCTestCase {
  func testOlderMatchingSnapshotsCannotConfirmOrReplaceLiveValues() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .off,
          activity: .connected,
          decision: decision(desired: false),
          modeLastUpdated: Date(timeIntervalSince1970: 100)
        )
      )
    )
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task { await store.selectMode(.charging) }
    await fulfillment(of: [client.setStarted], timeout: 1)
    let inFlightUpdate = expectation(description: "Older in-flight snapshot processed")
    let inFlightSubscription = store.objectWillChange.prefix(1).sink {
      inFlightUpdate.fulfill()
    }
    client.yield(.live(olderSnapshot(timestamp: 90)))
    await fulfillment(of: [inFlightUpdate], timeout: 1)
    assertInitialValuesRemainStale(store)

    client.succeedSet(with: .charging)
    await change.value
    assertInitialValuesRemainStale(store)

    let postChangeUpdate = expectation(description: "Older post-change snapshot processed")
    let postChangeSubscription = store.objectWillChange.prefix(1).sink {
      postChangeUpdate.fulfill()
    }
    client.yield(.live(olderSnapshot(timestamp: 95)))
    await fulfillment(of: [postChangeUpdate], timeout: 1)
    assertInitialValuesRemainStale(store)

    connection.cancel()
    await connection.value
    withExtendedLifetime((inFlightSubscription, postChangeSubscription)) {}
  }

  private func olderSnapshot(timestamp: TimeInterval) -> HomeAssistantEVChargingSnapshot {
    HomeAssistantEVChargingSnapshot(
      mode: .charging,
      activity: .charging(powerWatts: 7_000),
      decision: decision(desired: true),
      modeLastUpdated: Date(timeIntervalSince1970: timestamp)
    )
  }

  private func assertInitialValuesRemainStale(_ store: HomeAssistantEVChargingStore) {
    XCTAssertEqual(store.activity, .connected)
    XCTAssertEqual(store.decision, decision(desired: false))
    XCTAssertFalse(store.isActivityLive)
    XCTAssertFalse(store.isDecisionLive)
  }

  private func waitForValue<P: Publisher>(
    _ publisher: P,
    matching expectedValue: P.Output
  ) async where P.Output: Equatable, P.Failure == Never {
    let published = expectation(description: "Expected ordered value")
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

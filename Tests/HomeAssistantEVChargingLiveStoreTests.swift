import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantEVChargingLiveStoreTests: XCTestCase {
  func testConnectedStreamUpdatesMarksStaleAndRecoversWithoutProgressFlicker() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)

    client.yield(.live(snapshot(activity: .charging(powerWatts: 7_100))))
    await waitForValue(store.$activity, matching: .charging(powerWatts: 7_100))
    client.yield(.live(snapshot(activity: .charging(powerWatts: 7_024))))
    await waitForValue(store.$activity, matching: .charging(powerWatts: 7_024))
    client.yield(
      .reconnecting(snapshot(activity: .charging(powerWatts: 7_024)))
    )
    await waitForValue(store.$problem.compactMap(\.self), matching: .reconnecting)

    XCTAssertEqual(store.mode, .smart)
    XCTAssertEqual(store.activity, .charging(powerWatts: 7_024))
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.isActivityLive)
    XCTAssertFalse(store.isDecisionLive)
    XCTAssertEqual(store.decision, decision(desired: true))
    XCTAssertFalse(store.showsProgress)

    client.yield(.live(.init(mode: .charging, activity: .charging(powerWatts: 7_100))))
    await waitForValue(store.$isLive, matching: true)
    XCTAssertEqual(store.mode, .charging)
    XCTAssertEqual(store.activity, .charging(powerWatts: 7_100))
    XCTAssertTrue(store.isActivityLive)
    XCTAssertTrue(store.isDecisionLive)
    XCTAssertNil(store.problem)
    XCTAssertFalse(store.showsProgress)
    connection.cancel()
    await connection.value
  }

  func testLiveUpdateDuringModeChangeKeepsOptimisticModeAndUpdatesActivity() async {
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
          modeLastUpdated: Date(timeIntervalSince1970: 100)
        )
      )
    )
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .charging(powerWatts: 6_800))))
    await waitForValue(store.$activity, matching: .charging(powerWatts: 6_800))

    XCTAssertEqual(store.mode, .charging)
    XCTAssertFalse(store.showsProgress)
    client.succeedSet(with: .charging)
    await change.value
    XCTAssertEqual(store.mode, .charging)
    XCTAssertEqual(store.activity, .charging(powerWatts: 6_800))
    XCTAssertTrue(store.isActivityLive)
    XCTAssertFalse(store.isDecisionLive)
    XCTAssertFalse(store.showsProgress)
    connection.cancel()
    await connection.value
  }

  func testDifferingLiveModeDuringWriteWinsOverRequestConfirmation() async {
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
          modeLastUpdated: Date(timeIntervalSince1970: 100)
        )
      )
    )
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .smart,
          activity: .charging(powerWatts: 7_000),
          decision: decision(desired: true),
          modeLastUpdated: Date(timeIntervalSince1970: 102)
        )
      )
    )
    await waitForValue(store.$activity, matching: .charging(powerWatts: 7_000))
    client.succeedSet(with: .charging)
    await change.value

    XCTAssertEqual(store.mode, .smart)
    XCTAssertTrue(store.isLive)
    XCTAssertTrue(store.isDecisionLive)
    XCTAssertEqual(store.decision, decision(desired: true))
    connection.cancel()
    await connection.value
  }

  func testAcceptedInFlightDecisionBecomesLiveWhenModeChangeCompletes() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task { await store.selectMode(.charging) }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .charging,
          activity: .charging(powerWatts: 6_900),
          decision: decision(desired: true)
        )
      )
    )
    await waitForValue(store.$activity, matching: .charging(powerWatts: 6_900))
    XCTAssertFalse(store.isDecisionLive)
    client.succeedSet(with: .charging)
    await change.value
    XCTAssertTrue(store.isDecisionLive)
    XCTAssertEqual(store.decision, decision(desired: true))
    connection.cancel()
    await connection.value
  }

}

extension HomeAssistantEVChargingLiveStoreTests {
  func testFinishedStreamRetainsDecisionWithoutClaimingItIsLive() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .smart,
          activity: .connected,
          decision: decision(desired: true)
        )
      )
    )
    await waitForValue(store.$isDecisionLive, matching: true)

    client.finishUpdates()
    await waitForValue(store.$problem.compactMap(\.self), matching: .connectionUnavailable)

    XCTAssertEqual(store.decision, decision(desired: true))
    XCTAssertFalse(store.isDecisionLive)
    await connection.value
  }

  func testMatchingLiveConfirmationBeforeRequestCompletionAcceptsLaterExternalMode() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .charging,
          activity: .charging(powerWatts: 7_000),
          decision: decision(desired: true)
        )
      )
    )
    await waitForValue(
      store.$activity,
      matching: .charging(powerWatts: 7_000)
    )
    client.succeedSet(with: .charging)
    await change.value
    client.yield(
      .live(
        .init(
          mode: .smart,
          activity: .connected,
          decision: decision(desired: false)
        )
      )
    )
    await waitForValue(store.$mode.compactMap(\.self), matching: .smart)

    XCTAssertEqual(store.mode, .smart)
    XCTAssertEqual(store.activity, .connected)
    XCTAssertEqual(store.decision, decision(desired: false))
    XCTAssertTrue(store.isLive)
    connection.cancel()
    await connection.value
  }

  func testLiveRequestedModeWinsOverOlderRequestConfirmationWithoutFailure() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(.live(.init(mode: .charging, activity: .charging(powerWatts: 7_000))))
    await waitForValue(store.$activity, matching: .charging(powerWatts: 7_000))
    client.succeedSet(with: .off)
    await change.value

    XCTAssertEqual(store.mode, .charging)
    XCTAssertTrue(store.isLive)
    XCTAssertNil(store.problem)
    connection.cancel()
    await connection.value
  }

  func testStaleNonLiveSnapshotsDoNotOverwriteConfirmedMode() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.succeedSet(with: .charging)
    await change.value
    XCTAssertFalse(store.isDecisionLive)
    client.yield(.reconnecting(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$problem.compactMap(\.self), matching: .reconnecting)
    XCTAssertEqual(store.mode, .charging)

    client.yield(.unavailable(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$problem.compactMap(\.self), matching: .invalidResponse)
    XCTAssertEqual(store.mode, .charging)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.isActivityLive)
    XCTAssertFalse(store.isDecisionLive)
    connection.cancel()
    await connection.value
  }

  func testModeChangeCompletionDoesNotRestoreLivenessWhileReconnecting() async {
    let client = StreamingEVChargingClient()
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)

    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(.reconnecting(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$problem.compactMap(\.self), matching: .reconnecting)
    client.succeedSet(with: .charging)
    await change.value

    XCTAssertEqual(store.mode, .charging)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.isActivityLive)
    XCTAssertFalse(store.isDecisionLive)
    XCTAssertFalse(store.canSelectMode)
    XCTAssertEqual(store.problem, .reconnecting)
    connection.cancel()
    await connection.value
  }

  private func waitForValue<P: Publisher>(
    _ publisher: P,
    matching expectedValue: P.Output
  ) async where P.Output: Equatable, P.Failure == Never {
    let published = expectation(description: "Expected live store value published")
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

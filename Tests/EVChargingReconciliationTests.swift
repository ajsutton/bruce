import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class EVChargingReconciliationTests: XCTestCase {
  func testLiveUpdateWinsOverOlderLateReconciliationSnapshot() async {
    let setup = await connectedStore()
    let client = setup.client
    let store = setup.store
    let change = Task { await store.selectMode(.charging) }
    await fulfillment(of: [client.setStarted], timeout: 1)
    change.cancel()
    await change.value
    client.succeedSet(with: .charging)
    await fulfillment(of: [client.loadStarted], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .smart,
          activity: .connected,
          modeLastUpdated: Date(timeIntervalSince1970: 200)
        )
      )
    )
    await waitForValue(store.$mode.compactMap(\.self), matching: .smart)
    let handled = expectation(description: "Late reconciliation handled")
    let subscription = store.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in
      handled.fulfill()
    }

    client.succeedLoad(
      with: .init(
        mode: .off,
        activity: .switchedOff,
        modeLastUpdated: Date(timeIntervalSince1970: 100)
      )
    )
    await fulfillment(of: [handled], timeout: 1)

    XCTAssertEqual(store.mode, .smart)
    XCTAssertEqual(store.activity, .connected)
    XCTAssertTrue(store.isLive)
    XCTAssertTrue(store.isActivityLive)
    withExtendedLifetime(subscription) {}
    setup.connection.cancel()
    await setup.connection.value
  }
}

extension EVChargingReconciliationTests {
  func testNewerReconciliationAppliesTheCompleteSnapshot() async {
    let setup = await connectedStore()
    let client = setup.client
    let store = setup.store
    let change = Task { await store.selectMode(.charging) }
    await fulfillment(of: [client.setStarted], timeout: 1)
    change.cancel()
    await change.value
    client.yield(
      .live(
        .init(
          mode: .smart,
          activity: .charging(powerWatts: 7_000),
          modeLastUpdated: Date(timeIntervalSince1970: 200)
        )
      )
    )
    await waitForValue(store.$activity, matching: .charging(powerWatts: 7_000))
    client.succeedSet(with: .charging)
    await fulfillment(of: [client.loadStarted], timeout: 1)
    let handled = expectation(description: "Late reconciliation handled")
    let subscription = store.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in
      handled.fulfill()
    }

    XCTAssertFalse(store.isLive || store.isActivityLive)

    client.succeedLoad(
      with: .init(
        mode: .charging,
        activity: .switchedOff,
        modeLastUpdated: Date(timeIntervalSince1970: 300)
      )
    )
    await fulfillment(of: [handled], timeout: 1)

    XCTAssertEqual(store.mode, .charging)
    XCTAssertEqual(store.activity, .switchedOff)
    XCTAssertTrue(store.isLive)
    XCTAssertTrue(store.isActivityLive)
    client.yield(
      .live(
        .init(
          mode: .smart,
          activity: .connected,
          modeLastUpdated: Date(timeIntervalSince1970: 200)
        )
      )
    )
    await Task.yield()
    XCTAssertEqual(store.activity, .switchedOff)
    withExtendedLifetime(subscription) {}
    setup.connection.cancel()
    await setup.connection.value
  }

  func testTerminatedSubscriptionRejectsLateReconciliationSnapshot() async {
    let setup = await connectedStore()
    let client = setup.client
    let store = setup.store
    let connection = setup.connection
    let change = Task { await store.selectMode(.charging) }
    await fulfillment(of: [client.setStarted], timeout: 1)
    change.cancel()
    await change.value
    client.succeedSet(with: .charging)
    await fulfillment(of: [client.loadStarted], timeout: 1)
    client.finishUpdates()
    await waitForValue(store.$problem.compactMap(\.self), matching: .connectionUnavailable)
    let handled = expectation(description: "Reconciliation result rejected")
    let subscription = store.$isLoading.dropFirst().filter { !$0 }.sink { _ in
      handled.fulfill()
    }
    client.succeedLoad(
      with: .init(
        mode: .charging,
        activity: .charging(powerWatts: 7_000),
        modeLastUpdated: Date(timeIntervalSince1970: 100)
      )
    )
    await fulfillment(of: [handled], timeout: 1)

    XCTAssertFalse(store.isLive || store.isActivityLive)
    XCTAssertEqual(store.problem, .connectionUnavailable)
    withExtendedLifetime(subscription) {}
    connection.cancel()
    await connection.value
  }

  func testReconciliationStartedAfterTerminationRemainsStale() async {
    let setup = await connectedStore()
    let client = setup.client
    let store = setup.store
    let connection = setup.connection
    let change = Task { await store.selectMode(.charging) }
    await fulfillment(of: [client.setStarted], timeout: 1)
    change.cancel()
    await change.value
    client.finishUpdates()
    await waitForValue(store.$problem.compactMap(\.self), matching: .connectionUnavailable)
    client.succeedSet(with: .charging)
    await fulfillment(of: [client.loadStarted], timeout: 1)
    let handled = expectation(description: "Stale reconciliation handled")
    let subscription = store.$isLoading.dropFirst().filter { !$0 }.sink { _ in
      handled.fulfill()
    }
    client.succeedLoad(
      with: .init(
        mode: .charging,
        activity: .charging(powerWatts: 7_000),
        modeLastUpdated: Date(timeIntervalSince1970: 100)
      )
    )
    await fulfillment(of: [handled], timeout: 1)

    XCTAssertEqual(store.mode, .charging)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.isActivityLive)
    withExtendedLifetime(subscription) {}
    connection.cancel()
    await connection.value
  }

  func testTerminalStreamThenResubscriptionAcceptsFirstAuthoritativeMode() async {
    let setup = await connectedStore(allowsRestart: true)
    let client = setup.client
    let store = setup.store
    let firstConnection = setup.connection
    let change = Task { await store.selectMode(.charging) }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.succeedSet(with: .charging)
    await change.value
    client.finishUpdates()
    await waitForValue(store.$problem.compactMap(\.self), matching: .connectionUnavailable)
    await firstConnection.value
    let restarted = client.expectNextStreamStart()
    let secondConnection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [restarted], timeout: 1)
    client.yield(.live(.init(mode: .smart, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .smart)

    XCTAssertEqual(store.mode, .smart)
    XCTAssertTrue(store.isLive)
    secondConnection.cancel()
    await secondConnection.value
  }

  func testReplacementStreamUsesItsOwnTimestampSequenceDuringModeChange() async {
    let setup = await connectedStore(allowsRestart: true)
    let client = setup.client
    let store = setup.store
    let firstConnection = setup.connection
    client.yield(
      .live(
        .init(
          mode: .off,
          activity: .switchedOff,
          modeLastUpdated: Date(timeIntervalSince1970: 200)
        )
      )
    )
    await waitForValue(store.$activity, matching: .switchedOff)

    await store.synchronize(with: .connecting)
    client.finishUpdates()
    await firstConnection.value
    let restarted = client.expectNextStreamStart()
    let secondConnection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [restarted], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .off,
          activity: .connected,
          modeLastUpdated: Date(timeIntervalSince1970: 100)
        )
      )
    )
    await waitForValue(store.$isLive, matching: true)

    let change = Task { await store.selectMode(.charging) }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .smart,
          activity: .connected,
          modeLastUpdated: Date(timeIntervalSince1970: 101)
        )
      )
    )
    client.succeedSet(with: .charging)
    await change.value

    XCTAssertEqual(store.mode, .smart)
    XCTAssertTrue(store.isLive)
    secondConnection.cancel()
    await secondConnection.value
  }

  private func connectedStore(allowsRestart: Bool = false) async -> ConnectedStore {
    let client = StreamingEVChargingClient()
    client.started.assertForOverFulfill = !allowsRestart
    let store = HomeAssistantEVChargingStore(client: client)
    let connection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [client.started], timeout: 1)
    client.yield(.live(.init(mode: .off, activity: .connected)))
    await waitForValue(store.$mode.compactMap(\.self), matching: .off)
    return ConnectedStore(client: client, store: store, connection: connection)
  }

  private func waitForValue<P: Publisher>(
    _ publisher: P,
    matching expectedValue: P.Output
  ) async where P.Output: Equatable, P.Failure == Never {
    let published = expectation(description: "Expected reconciliation value published")
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
      lastSuccessfulURL: URL(string: "https://home.example") ?? URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }

  private struct ConnectedStore {
    let client: StreamingEVChargingClient
    let store: HomeAssistantEVChargingStore
    let connection: Task<Void, Never>
  }
}

extension EVChargingReconciliationTests {
  func testRefreshDuringModeChangePreservesNewerLiveMode() async {
    let setup = await connectedStore(allowsRestart: true)
    let client = setup.client
    let store = setup.store
    let firstConnection = setup.connection
    let change = Task { await store.selectMode(.charging) }
    await fulfillment(of: [client.setStarted], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .smart,
          activity: .charging(powerWatts: 1_234),
          modeLastUpdated: Date(timeIntervalSince1970: 200)
        )
      )
    )
    await waitForValue(store.$activity, matching: .charging(powerWatts: 1_234))

    firstConnection.cancel()
    await firstConnection.value
    let restarted = client.expectNextStreamStart()
    let secondConnection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [restarted], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .smart,
          activity: .connected,
          modeLastUpdated: Date(timeIntervalSince1970: 200)
        )
      )
    )
    await waitForValue(store.$isLive, matching: true)
    client.succeedSet(with: .charging)
    await change.value

    XCTAssertEqual(store.mode, .smart)
    XCTAssertTrue(store.isLive)
    secondConnection.cancel()
    await secondConnection.value
  }

  func testReplacementStreamRejectsReconciliationFromPreviousObservation() async {
    let setup = await connectedStore(allowsRestart: true)
    let client = setup.client
    let store = setup.store
    let firstConnection = setup.connection
    let change = Task { await store.selectMode(.charging) }
    await fulfillment(of: [client.setStarted], timeout: 1)
    change.cancel()
    await change.value
    client.succeedSet(with: .charging)
    await fulfillment(of: [client.loadStarted], timeout: 1)

    firstConnection.cancel()
    await firstConnection.value
    let restarted = client.expectNextStreamStart()
    let secondConnection = Task {
      await store.synchronize(with: .connected(credentials))
    }
    await fulfillment(of: [restarted], timeout: 1)
    client.yield(
      .live(
        .init(
          mode: .smart,
          activity: .connected,
          modeLastUpdated: Date(timeIntervalSince1970: 200)
        )
      )
    )
    await waitForValue(store.$mode.compactMap(\.self), matching: .smart)

    let handled = expectation(description: "Old reconciliation rejected")
    let subscription = store.$isLoading.dropFirst().filter { !$0 }.sink { _ in
      handled.fulfill()
    }
    client.succeedLoad(
      with: .init(
        mode: .off,
        activity: .switchedOff,
        modeLastUpdated: Date(timeIntervalSince1970: 300)
      )
    )
    await fulfillment(of: [handled], timeout: 1)

    XCTAssertEqual(store.mode, .smart)
    XCTAssertEqual(store.activity, .connected)
    XCTAssertTrue(store.isLive)
    withExtendedLifetime(subscription) {}
    secondConnection.cancel()
    await secondConnection.value
  }
}

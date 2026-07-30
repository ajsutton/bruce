import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeEnergyStreamHistoryTests: XCTestCase {
  func testOverflowRetainsOnlyNewestSnapshot() async throws {
    typealias Update = HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>
    var continuation: HomeAssistantHomeEnergyUpdateStream.Continuation?
    let updates = HomeAssistantHomeEnergyUpdateStream {
      continuation = $0
    }

    let streamContinuation = try XCTUnwrap(continuation)
    streamContinuation.yield(.live(snapshot(charge: 34)))
    streamContinuation.yield(.live(snapshot(charge: 43)))
    continuation?.finish()

    var iterator = updates.makeAsyncIterator()
    guard case .live(let newestSnapshot) = try await iterator.next() else {
      XCTFail("Expected the newest live snapshot")
      return
    }
    XCTAssertEqual(newestSnapshot.batteryStateOfCharge, 43)
    let remainingUpdate = try await iterator.next()
    XCTAssertNil(remainingUpdate)
  }

  func testControlTransitionSurvivesBlockedConsumerBurst() async throws {
    typealias Update = HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>
    var continuation: HomeAssistantHomeEnergyUpdateStream.Continuation?
    let updates = HomeAssistantHomeEnergyUpdateStream {
      continuation = $0
    }
    let streamContinuation = try XCTUnwrap(continuation)

    streamContinuation.yield(.refreshing(snapshot(charge: 33)))
    streamContinuation.yield(.reconnecting(snapshot(charge: 34)))
    streamContinuation.yield(.live(snapshot(charge: 43)))
    streamContinuation.yield(.live(snapshot(charge: 44)))
    streamContinuation.finish()

    var iterator = updates.makeAsyncIterator()
    guard case .reconnecting(let reconnecting) = try await iterator.next() else {
      XCTFail("Expected the reconnect transition")
      return
    }
    guard case .live(let live) = try await iterator.next() else {
      XCTFail("Expected the newest live snapshot")
      return
    }
    XCTAssertEqual(reconnecting.batteryStateOfCharge, 44)
    XCTAssertEqual(live.batteryStateOfCharge, 44)
    let remainingUpdate = try await iterator.next()
    XCTAssertNil(remainingUpdate)
  }

  func testConcurrentDrainKeepsNewestControlBeforeLiveValue() async throws {
    typealias Update = HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>
    var continuation: HomeAssistantHomeEnergyUpdateStream.Continuation?
    let updates = HomeAssistantHomeEnergyUpdateStream {
      continuation = $0
    }
    let streamContinuation = try XCTUnwrap(continuation)
    var iterator = updates.makeAsyncIterator()
    let waitingConsumer = Task {
      try await iterator.next()
    }

    streamContinuation.yield(.refreshing(snapshot(charge: 33)))
    guard case .refreshing = try await waitingConsumer.value else {
      XCTFail("Expected the control update delivered to the waiting consumer")
      return
    }
    streamContinuation.yield(.refreshing(snapshot(charge: 34)))
    streamContinuation.yield(.reconnecting(snapshot(charge: 35)))
    streamContinuation.yield(.live(snapshot(charge: 43)))
    streamContinuation.yield(.live(snapshot(charge: 44)))
    streamContinuation.finish()

    guard case .reconnecting(let reconnecting) = try await iterator.next() else {
      XCTFail("Expected the newest pending control transition")
      return
    }
    guard case .live(let live) = try await iterator.next() else {
      XCTFail("Expected the newest live value after the control transition")
      return
    }
    XCTAssertEqual(reconnecting.batteryStateOfCharge, 44)
    XCTAssertEqual(live.batteryStateOfCharge, 44)
    let remainingUpdate = try await iterator.next()
    XCTAssertNil(remainingUpdate)
  }

  func testCoalescedControlUsesNewestLiveGenerationAndStates() async throws {
    typealias Stream = HomeAssistantBufferedUpdateStream<HomeAssistantStateUpdate>
    var continuation: Stream.Continuation?
    let updates = Stream {
      continuation = $0
    }
    let streamContinuation = try XCTUnwrap(continuation)
    let oldGeneration = UUID()
    let liveGeneration = UUID()
    streamContinuation.yield(
      .reconnecting(
        try states(charge: 34),
        generation: oldGeneration
      )
    )
    streamContinuation.yield(
      .live(
        try states(charge: 44),
        generation: liveGeneration
      )
    )
    streamContinuation.finish()

    var iterator = updates.makeAsyncIterator()
    let reconnectingUpdate = try await iterator.next()
    let reconnecting = try XCTUnwrap(reconnectingUpdate)
    XCTAssertEqual(reconnecting.phase, .reconnecting)
    XCTAssertEqual(reconnecting.generation, liveGeneration)
    XCTAssertEqual(
      HomeAssistantHomeEnergySnapshot(states: reconnecting.states)
        .batteryStateOfCharge,
      44
    )
    let liveUpdate = try await iterator.next()
    let live = try XCTUnwrap(liveUpdate)
    XCTAssertEqual(live.phase, .live)
    XCTAssertEqual(live.generation, liveGeneration)
  }

  func testBurstCoalescesToNewestBatteryReadingAtGraphResolution() async throws {
    let firstTimestamp = Date(timeIntervalSince1970: 700_000)
    let timestamps = [
      firstTimestamp,
      firstTimestamp.addingTimeInterval(1),
      firstTimestamp.addingTimeInterval(2),
      firstTimestamp.addingTimeInterval(
        HomeEnergyHistorySampling.interval
      ),
    ]
    let dates = ControlledHomeEnergyDateSequence(timestamps)
    let source = ControlledStateSource()
    let historyLoader = InitialBatteryHistoryLoader(
      history: history(endingAt: firstTimestamp.addingTimeInterval(-10))
    )
    let loader = HomeAssistantHomeEnergyStream(
      states: HomeAssistantStateHub(source: source),
      loader: historyLoader
    )
    let store = HomeAssistantHomeEnergyStore(loader: loader, now: dates.next)
    let historyLoaded = expectation(description: "Initial battery history loaded")
    let historySubscription = store.batteryHistoryStore.$hasUsableHistory
      .filter { $0 }
      .prefix(1)
      .sink { _ in historyLoaded.fulfill() }
    let synchronization = Task {
      await store.synchronize(with: .connected(credentials()))
    }
    await fulfillment(of: [source.started, historyLoaded], timeout: 1)
    var parentChangeCount = 0
    let parentSubscription = store.objectWillChange.sink {
      parentChangeCount += 1
    }

    for (index, charge) in [34.0, 41, 43].enumerated() {
      source.yield(.live(try states(charge: charge)))
      await fulfillment(of: [dates.requested(at: index)], timeout: 1)
    }
    await Task.yield()
    let changesBeforeEquivalentUpdate = parentChangeCount

    source.yield(.live(try states(charge: 43.4)))
    await fulfillment(of: [dates.requested(at: 3)], timeout: 1)
    await Task.yield()

    XCTAssertEqual(store.snapshot.batteryStateOfCharge, 43)
    XCTAssertEqual(parentChangeCount, changesBeforeEquivalentUpdate)
    assertHistory(store.batteryHistoryStore.batteryHistory, [20, 43.4], timestamps.last)
    synchronization.cancel()
    await synchronization.value
    withExtendedLifetime(parentSubscription) {}
    withExtendedLifetime(historySubscription) {}
  }

  private func assertHistory(
    _ history: HomeEnergyBatteryHistory,
    _ values: [Double],
    _ end: Date?
  ) {
    XCTAssertEqual(
      history.readings.compactMap(\.stateOfCharge),
      values
    )
    XCTAssertEqual(Optional(history.interval.end), end)
  }

  private func history(endingAt end: Date) -> HomeEnergyBatteryHistory {
    let start = end.addingTimeInterval(-24 * 60 * 60)
    return HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, end: end),
      readings: [.init(timestamp: start, stateOfCharge: 20)]
    )
  }

  private func states(charge: Double) throws -> [HomeAssistantState] {
    try JSONDecoder().decode(
      [HomeAssistantState].self,
      from: Data(
        """
        [{
          "entity_id":"\(HomeAssistantHomeEnergySnapshot.batteryStateOfChargeEntityID)",
          "state":"\(charge)",
          "attributes":{}
        }]
        """.utf8
      )
    )
  }

  private func snapshot(charge: Double) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: nil,
      batteryStateOfCharge: charge,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: nil,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil
    )
  }

  private func credentials() -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

private struct InitialBatteryHistoryLoader: HomeAssistantHomeEnergyLoading {
  let history: HomeEnergyBatteryHistory

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }

  func loadHomeEnergyBatteryHistory() async throws -> HomeEnergyBatteryHistory {
    history
  }
}

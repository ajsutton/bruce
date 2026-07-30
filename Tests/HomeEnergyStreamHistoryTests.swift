import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeEnergyStreamHistoryTests: XCTestCase {
  func testOverflowRetainsOnlyNewestSnapshotAndMarksItForBackfill() async throws {
    typealias Update = HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>
    var continuation: AsyncThrowingStream<Update, any Error>.Continuation?
    let updates = AsyncThrowingStream<Update, any Error>(
      bufferingPolicy: .bufferingNewest(1)
    ) {
      continuation = $0
    }

    HomeAssistantHomeEnergyStream.yield(
      .live(snapshot(charge: 34)),
      to: try XCTUnwrap(continuation)
    )
    HomeAssistantHomeEnergyStream.yield(
      .live(snapshot(charge: 43)),
      to: try XCTUnwrap(continuation)
    )
    continuation?.finish()

    var iterator = updates.makeAsyncIterator()
    guard case .live(let newestSnapshot) = try await iterator.next() else {
      XCTFail("Expected the newest live snapshot")
      return
    }
    XCTAssertEqual(newestSnapshot.batteryStateOfCharge, 43)
    XCTAssertTrue(newestSnapshot.requiresHistoryBackfill)
    let remainingUpdate = try await iterator.next()
    XCTAssertNil(remainingUpdate)
  }

  func testBurstTransitionsAndRepeatedObservationsReachBatteryHistory() async throws {
    let firstTimestamp = Date(timeIntervalSince1970: 700_000)
    let timestamps = (0..<4).map {
      firstTimestamp.addingTimeInterval(TimeInterval($0))
    }
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

    for (index, charge) in [34.0, 41, 43, 43].enumerated() {
      source.yield(.live(try states(charge: charge)))
      await fulfillment(of: [dates.requested(at: index)], timeout: 1)
    }

    XCTAssertEqual(
      store.batteryHistoryStore.batteryHistory.readings.compactMap(
        \.stateOfCharge
      ),
      [20, 34, 41, 43]
    )
    XCTAssertEqual(
      store.batteryHistoryStore.batteryHistory.interval.end,
      timestamps.last
    )
    synchronization.cancel()
    await synchronization.value
    withExtendedLifetime(historySubscription) {}
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

import Combine
import XCTest

@testable import Bruce

@MainActor
final class BatteryHistorySamplingTests: XCTestCase {
  func testPendingLiveBatteryBurstMergesOnlyNewestSample() async {
    let start = Date(timeIntervalSince1970: 600_000)
    let end = start.addingTimeInterval(24 * 60 * 60)
    let dates = ControlledHomeEnergyDateSequence([
      end.addingTimeInterval(1),
      end.addingTimeInterval(2),
      end.addingTimeInterval(3),
    ])
    let loader = ControlledBatteryHistoryLoader(
      batteryRequestCount: 1,
      providesContinuousEnergyUpdates: true
    )
    let store = HomeAssistantHomeEnergyStore(loader: loader, now: dates.next)
    let synchronization = Task {
      await store.synchronize(with: .ready(credentials()))
    }
    await fulfillment(
      of: [loader.updateStreamStarted, loader.batteryStarted(at: 0)],
      timeout: 1
    )

    for (index, charge) in [31.0, 32, 33].enumerated() {
      loader.yield(.live(snapshot(charge: charge)))
      await fulfillment(of: [dates.requested(at: index)], timeout: 1)
    }
    await completeBatteryLoad(
      on: store,
      loader: loader,
      history: batteryHistory(start: start, end: end)
    )

    XCTAssertEqual(
      store.batteryHistoryStore.batteryHistory.readings.filter {
        $0.timestamp > end
      },
      [.init(timestamp: end.addingTimeInterval(3), stateOfCharge: 33)]
    )
    synchronization.cancel()
    loader.finishUpdates()
    await synchronization.value
  }

  func testSingleLiveBatteryUpdateFlushesAfterSampleBoundary() async {
    let start = Date(timeIntervalSince1970: 700_000)
    let end = start.addingTimeInterval(24 * 60 * 60)
    let initialHistory = batteryHistory(start: start, end: end)
    let delay = ControlledHomeEnergyDelay(delayCount: 1)
    let store = HomeEnergyBatteryHistoryStore(
      loader: ControlledBatteryHistoryLoader(batteryRequestCount: 0),
      batteryHistory: initialHistory,
      sampleSleep: { try? await delay.sleep($0) }
    )
    let flushed = expectation(description: "Trailing battery sample flushed")
    let subscription = store.$batteryHistory
      .dropFirst()
      .filter { $0 != initialHistory }
      .prefix(1)
      .sink { _ in flushed.fulfill() }

    store.record(
      snapshot: snapshot(charge: 33),
      at: end.addingTimeInterval(0.001)
    )
    XCTAssertEqual(store.batteryHistory, initialHistory)

    await fulfillment(of: [delay.started(at: 0)], timeout: 1)
    delay.finish(0)
    await fulfillment(of: [flushed], timeout: 1)
    XCTAssertEqual(store.batteryHistory.readings.last?.stateOfCharge, 33)
    withExtendedLifetime(subscription) {}
  }

  func testBatteryAvailabilityTransitionPublishesImmediately() {
    let start = Date(timeIntervalSince1970: 750_000)
    let end = start.addingTimeInterval(24 * 60 * 60)
    let store = HomeEnergyBatteryHistoryStore(
      loader: ControlledBatteryHistoryLoader(batteryRequestCount: 0),
      batteryHistory: batteryHistory(start: start, end: end)
    )
    let timestamp = end.addingTimeInterval(1)

    store.record(snapshot: snapshot(charge: nil), at: timestamp)

    XCTAssertEqual(store.batteryHistory.interval.end, timestamp)
    XCTAssertNil(store.batteryHistory.readings.last?.stateOfCharge)
  }

  private func completeBatteryLoad(
    on store: HomeAssistantHomeEnergyStore,
    loader: ControlledBatteryHistoryLoader,
    history: HomeEnergyBatteryHistory
  ) async {
    let completed = expectation(description: "Battery history load completed")
    let subscription = store.batteryHistoryStore.$isLoading
      .dropFirst()
      .filter { !$0 }
      .prefix(1)
      .sink { _ in completed.fulfill() }
    loader.succeedBattery(0, with: history)
    await fulfillment(of: [completed], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  private func batteryHistory(
    start: Date,
    end: Date
  ) -> HomeEnergyBatteryHistory {
    HomeEnergyBatteryHistory(
      interval: DateInterval(start: start, end: end),
      readings: [.init(timestamp: start, stateOfCharge: 20)]
    )
  }

  private func snapshot(charge: Double?) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: 8.4,
      batteryStateOfCharge: charge,
      homeConsumptionKilowatts: 3.1,
      gridPowerKilowatts: -2.7,
      generalPriceDollarsPerKilowattHour: 0.22,
      feedInPriceDollarsPerKilowattHour: 0.07
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

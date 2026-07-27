import Combine
import XCTest

@testable import Bruce

@MainActor
final class OptimisticClimateControlTimeoutTests: XCTestCase {
  func testMismatchingLiveStateRollsBackAfterConfirmationTimeout() async {
    let fixture = await loadedStore()
    let store = fixture.store
    let reading = fixture.reading

    await store.setPower(for: reading, isOn: false)
    await fulfillment(of: [fixture.sleeper.started], timeout: 1)
    fixture.loader.yieldRequest(0, update: .live([reading]))
    XCTAssertEqual(store.readings.first?.powerState, .off)
    let rejected = expectation(description: "Unconfirmed command rejected")
    let subscription = store.$controlProblem.compactMap { $0 }.prefix(1).sink { _ in
      rejected.fulfill()
    }

    fixture.sleeper.finish()
    await fulfillment(of: [rejected], timeout: 1)

    assertRolledBack(store, reading: reading)
    fixture.loader.finishRequest(0)
    await fixture.load.value
    withExtendedLifetime(subscription) {}
  }

  func testMissingConfirmationRollsBackAfterTimeout() async {
    let fixture = await loadedStore()
    let store = fixture.store
    let reading = fixture.reading

    await store.setPower(for: reading, isOn: false)
    await fulfillment(of: [fixture.sleeper.started], timeout: 1)
    XCTAssertEqual(store.readings.first?.powerState, .off)
    let rejected = expectation(description: "Missing confirmation rejected")
    let subscription = store.$controlProblem.compactMap { $0 }.prefix(1).sink { _ in
      rejected.fulfill()
    }

    fixture.sleeper.finish()
    await fulfillment(of: [rejected], timeout: 1)

    assertRolledBack(store, reading: reading)
    fixture.loader.finishRequest(0)
    await fixture.load.value
    withExtendedLifetime(subscription) {}
  }

  private func loadedStore() async -> TimeoutControlFixture {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let controller = RecordingClimateController()
    let sleeper = ControlledConfirmationSleeper()
    let store = HomeAssistantTemperatureStore(
      loader: loader,
      controller: controller,
      sleep: sleeper.sleep
    )
    let reading = controllableReading()
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    let live = expectation(description: "Live climate state published")
    let subscription = store.$isLive.dropFirst().sink { isLive in
      if isLive {
        live.fulfill()
      }
    }
    loader.yieldRequest(0, update: .live([reading]))
    await fulfillment(of: [live], timeout: 1)
    withExtendedLifetime(subscription) {}
    return TimeoutControlFixture(
      store: store,
      reading: reading,
      loader: loader,
      sleeper: sleeper,
      load: load
    )
  }

  private func controllableReading() -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: "climate.air_conditioner",
      name: "Air Conditioner",
      value: 22,
      targetValue: 23,
      unit: "°C",
      powerState: .poweredOn,
      kind: .airConditioner,
      operatingMode: .cooling,
      availableModes: [.automatic, .cooling]
    )
  }

  private func assertRolledBack(
    _ store: HomeAssistantTemperatureStore,
    reading: HomeAssistantTemperatureReading
  ) {
    XCTAssertEqual(store.readings.first?.powerState, .poweredOn)
    XCTAssertFalse(store.isControlling(entityID: reading.id))
    XCTAssertEqual(
      store.controlProblem,
      .init(message: "Bruce couldn’t update Air Conditioner.")
    )
  }
}

@MainActor
private struct TimeoutControlFixture {
  let store: HomeAssistantTemperatureStore
  let reading: HomeAssistantTemperatureReading
  let loader: ControlledTemperatureLoader
  let sleeper: ControlledConfirmationSleeper
  let load: Task<Void, Never>
}

private final class ControlledConfirmationSleeper: @unchecked Sendable {
  let started = XCTestExpectation(description: "Confirmation timeout started")

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  func sleep(_: Duration) async {
    await withCheckedContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func finish() {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume()
  }
}

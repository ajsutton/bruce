import Combine
import XCTest

@testable import Bruce

@MainActor
final class DemoSessionTests: XCTestCase {
  func testLeavingDemoStopsObservationsAndClearsPresentedData() async {
    let session = DemoSession()
    let climateReady = expectation(description: "Demo climate ready")
    let garageReady = expectation(description: "Demo garage ready")
    let chargerReady = expectation(description: "Demo charger ready")
    let flowReady = expectation(description: "Demo flow history ready")
    let batteryReady = expectation(description: "Demo battery history ready")
    let pricesReady = expectation(description: "Demo price history ready")
    let subscriptions = [
      session.homeEnergyStore.flowHistoryStore.$hasUsableHistory.first(where: { $0 })
        .sink { _ in flowReady.fulfill() },
      session.homeEnergyStore.batteryHistoryStore.$hasUsableHistory.first(where: { $0 })
        .sink { _ in batteryReady.fulfill() },
      session.homeEnergyStore.priceHistoryStore.$hasUsableHistory.first(where: { $0 })
        .sink { _ in pricesReady.fulfill() },
      session.temperatureStore.$isLive.first(where: { $0 }).sink { _ in climateReady.fulfill() },
      session.garageDoorStore.$isLive.first(where: { $0 }).sink { _ in garageReady.fulfill() },
      session.chargingStore.$isLive.first(where: { $0 }).sink { _ in chargerReady.fulfill() },
    ]
    let observation = Task { await session.observe() }
    defer { observation.cancel() }
    await fulfillment(
      of: [climateReady, garageReady, chargerReady, flowReady, batteryReady, pricesReady],
      timeout: 3)
    XCTAssertFalse(session.temperatureStore.readings.isEmpty)
    XCTAssertFalse(session.garageDoorStore.doors.isEmpty)
    XCTAssertTrue(session.homeEnergyStore.snapshot.hasReadings)
    let stopped = expectation(description: "Demo observation cancelled")
    observation.cancel()
    let completion = Task {
      await observation.value
      stopped.fulfill()
    }
    defer { completion.cancel() }
    await fulfillment(of: [stopped], timeout: 3)
    XCTAssertTrue(session.temperatureStore.readings.isEmpty)
    XCTAssertTrue(session.garageDoorStore.doors.isEmpty)
    XCTAssertNil(session.chargingStore.mode)
    XCTAssertFalse(session.homeEnergyStore.snapshot.hasReadings)
    withExtendedLifetime(subscriptions) {}
  }
}

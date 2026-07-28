import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantTemperatureCompletionTests: XCTestCase {
  func testFiniteStreamCanCompleteAfterPublishingLiveReadings() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let store = HomeAssistantTemperatureStore(loader: loader)
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)

    loader.succeedRequest(0, with: [reading])
    await load.value

    XCTAssertFalse(store.isLive)
    XCTAssertNil(store.problem)
  }

  func testContinuousStreamCompletionReportsConnectionUnavailable() async {
    let loader = ControlledTemperatureLoader(
      requestCount: 1,
      providesContinuousUpdates: true
    )
    let store = HomeAssistantTemperatureStore(loader: loader)
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)

    loader.succeedRequest(0, with: [reading])
    await load.value

    XCTAssertFalse(store.isLive)
    XCTAssertEqual(store.problem, .connectionUnavailable)
  }

  private var reading: HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: "climate.bedroom",
      name: "Bedroom",
      value: 22,
      targetValue: 23,
      unit: "°C",
      powerState: .poweredOn
    )
  }
}

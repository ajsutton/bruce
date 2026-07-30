import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantGarageDoorStreamTests: XCTestCase {
  func testRegistryFailureStillPublishesDoorOnlyStatus() async throws {
    let source = ControlledStateSource()
    let stream = HomeAssistantGarageDoorStream(
      states: source,
      registryLoader: FailingGarageDoorRegistryLoader()
    )
    let probe = AsyncThrowingStreamTestProbe(stream.garageDoorUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(.live(try garageDoorStates()))
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let update = try XCTUnwrap(try probe.value(at: 0))
    guard case .live(let doors) = update else {
      return XCTFail("Expected a live garage door update.")
    }

    XCTAssertEqual(doors.first?.name, "Side Entry")
    XCTAssertEqual(doors.first?.doorState, .opening)
    XCTAssertEqual(doors.first?.lightState, .unavailable)
    XCTAssertEqual(doors.first?.lockState, .unavailable)
    XCTAssertNil(doors.first?.lightEntityID)
    XCTAssertNil(doors.first?.lockEntityID)
  }

  func testNewGenerationControlUsesCachedDoorsUntilRegistryRefresh() async throws {
    let source = ControlledStateSource()
    let registryLoader = QueueGarageDoorRegistryLoader(
      names: ["Old Garage", "New Garage"]
    )
    let stream = HomeAssistantGarageDoorStream(
      states: source,
      registryLoader: registryLoader
    )
    let probe = AsyncThrowingStreamTestProbe(stream.garageDoorUpdates())
    await fulfillment(of: [source.started], timeout: 1)
    let oldGeneration = UUID()
    let newGeneration = UUID()

    source.yield(
      .live(try garageDoorStates(), generation: oldGeneration)
    )
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    source.yield(
      .reconnecting(try garageDoorStates(), generation: newGeneration)
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    source.yield(
      .live(try garageDoorStates(), generation: newGeneration)
    )
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    guard case .live(let initial) = try probe.value(at: 0),
      case .reconnecting(let reconnecting) = try probe.value(at: 1),
      case .live(let refreshed) = try probe.value(at: 2)
    else {
      return XCTFail("Expected live, reconnecting, then refreshed live doors.")
    }
    XCTAssertEqual(initial.first?.name, "Old Garage")
    XCTAssertEqual(reconnecting.first?.name, "Old Garage")
    XCTAssertEqual(refreshed.first?.name, "New Garage")
    XCTAssertEqual(registryLoader.requestCount, 2)
  }

  private func garageDoorStates() throws -> [HomeAssistantState] {
    try JSONDecoder().decode(
      [HomeAssistantState].self,
      from: Data(
        """
        [
          {
            "entity_id": "cover.side_entry",
            "state": "opening",
            "attributes": {
              "device_class": "garage",
              "friendly_name": "Side Entry",
              "supported_features": 15
            }
          }
        ]
        """.utf8
      )
    )
  }
}

private final class QueueGarageDoorRegistryLoader:
  HomeAssistantGarageDoorRegistryLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var names: [String]
  private var storedRequestCount = 0

  init(names: [String]) {
    self.names = names
  }

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func loadGarageDoorRegistry() async throws -> HomeAssistantGarageDoorRegistry {
    let name = lock.withLock {
      storedRequestCount += 1
      return names.removeFirst()
    }
    return HomeAssistantGarageDoorRegistry(
      deviceIDByEntityID: ["cover.side_entry": "garage"],
      deviceNameByID: ["garage": name]
    )
  }
}

private struct FailingGarageDoorRegistryLoader:
  HomeAssistantGarageDoorRegistryLoading
{
  func loadGarageDoorRegistry() async throws -> HomeAssistantGarageDoorRegistry {
    throw HomeAssistantAPIError.invalidResponse
  }
}

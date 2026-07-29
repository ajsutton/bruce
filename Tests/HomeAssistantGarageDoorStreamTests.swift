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

private struct FailingGarageDoorRegistryLoader:
  HomeAssistantGarageDoorRegistryLoading
{
  func loadGarageDoorRegistry() async throws -> HomeAssistantGarageDoorRegistry {
    throw HomeAssistantAPIError.invalidResponse
  }
}

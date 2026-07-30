import XCTest

@testable import Bruce

final class HomeEnergyAvailabilityBufferTests: XCTestCase {
  func testAvailabilityTransitionSurvivesBlockedEnergyConsumer() async throws {
    var continuation: HomeAssistantHomeEnergyUpdateStream.Continuation?
    let updates = HomeAssistantHomeEnergyUpdateStream {
      continuation = $0
    }
    let streamContinuation = try XCTUnwrap(continuation)
    streamContinuation.yield(.live(snapshot(grid: nil)))
    streamContinuation.yield(.live(snapshot(grid: 2)))
    streamContinuation.yield(.live(snapshot(grid: 3)))
    streamContinuation.finish()

    var iterator = updates.makeAsyncIterator()
    guard case .live(let unavailable) = try await iterator.next() else {
      XCTFail("Expected the unavailable transition")
      return
    }
    guard case .live(let recovered) = try await iterator.next() else {
      XCTFail("Expected the recovered live snapshot")
      return
    }
    XCTAssertNil(unavailable.gridPowerKilowatts)
    XCTAssertEqual(recovered.gridPowerKilowatts, 3)
    let remainingUpdate = try await iterator.next()
    XCTAssertNil(remainingUpdate)
  }

  func testAvailabilityTransitionSurvivesBlockedStateConsumer() async throws {
    typealias Stream = HomeAssistantBufferedUpdateStream<HomeAssistantStateUpdate>
    var continuation: Stream.Continuation?
    let updates = Stream {
      continuation = $0
    }
    let streamContinuation = try XCTUnwrap(continuation)
    streamContinuation.yield(.live(try flowStates(grid: "unavailable")))
    streamContinuation.yield(.live(try flowStates(grid: "2")))
    streamContinuation.yield(.live(try flowStates(grid: "3")))
    streamContinuation.finish()

    var iterator = updates.makeAsyncIterator()
    let unavailableUpdate = try await iterator.next()
    let recoveredUpdate = try await iterator.next()
    let unavailable = try XCTUnwrap(unavailableUpdate)
    let recovered = try XCTUnwrap(recoveredUpdate)
    XCTAssertNil(
      HomeAssistantHomeEnergySnapshot(states: unavailable.states)
        .gridPowerKilowatts
    )
    XCTAssertEqual(
      HomeAssistantHomeEnergySnapshot(states: recovered.states)
        .gridPowerKilowatts,
      3
    )
    let remainingUpdate = try await iterator.next()
    XCTAssertNil(remainingUpdate)
  }

  private func flowStates(grid: String) throws -> [HomeAssistantState] {
    try JSONDecoder().decode(
      [HomeAssistantState].self,
      from: Data(
        """
        [{
          "entity_id":"\(HomeAssistantHomeEnergySnapshot.gridPowerEntityID)",
          "state":"\(grid)",
          "attributes":{}
        }]
        """.utf8
      )
    )
  }

  private func snapshot(grid: Double?) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: nil,
      batteryStateOfCharge: 34,
      homeConsumptionKilowatts: nil,
      gridPowerKilowatts: grid,
      generalPriceDollarsPerKilowattHour: nil,
      feedInPriceDollarsPerKilowattHour: nil
    )
  }
}

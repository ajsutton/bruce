import XCTest

@testable import Bruce

final class EVChargingUpdateBufferTests: XCTestCase {
  func testRefreshTransitionSurvivesBlockedConsumer() async throws {
    var continuation: HomeAssistantEVChargingUpdateStream.Continuation?
    let updates = HomeAssistantEVChargingUpdateStream {
      continuation = $0
    }
    let streamContinuation = try XCTUnwrap(continuation)
    let initial = snapshot(desired: false)
    let latest = snapshot(desired: true)

    streamContinuation.yield(.refreshing(initial))
    streamContinuation.yield(.live(latest))
    streamContinuation.finish()

    var iterator = updates.makeAsyncIterator()
    let refreshing = try await iterator.next()
    let live = try await iterator.next()
    XCTAssertEqual(refreshing, .refreshing(latest))
    XCTAssertEqual(live, .live(latest))
    let remainingUpdate = try await iterator.next()
    XCTAssertNil(remainingUpdate)
  }

  func testUnavailableTransitionSurvivesBlockedConsumer() async throws {
    var continuation: HomeAssistantEVChargingUpdateStream.Continuation?
    let updates = HomeAssistantEVChargingUpdateStream {
      continuation = $0
    }
    let streamContinuation = try XCTUnwrap(continuation)
    let initial = snapshot(desired: false)
    let latest = snapshot(desired: true)

    streamContinuation.yield(.unavailable(initial))
    streamContinuation.yield(.live(latest))
    streamContinuation.finish()

    var iterator = updates.makeAsyncIterator()
    let unavailable = try await iterator.next()
    let live = try await iterator.next()
    XCTAssertEqual(unavailable, .unavailable(latest))
    XCTAssertEqual(live, .live(latest))
    let remainingUpdate = try await iterator.next()
    XCTAssertNil(remainingUpdate)
  }

  private func snapshot(desired: Bool) -> HomeAssistantEVChargingSnapshot {
    HomeAssistantEVChargingSnapshot(
      mode: .smart,
      activity: .connected,
      decision: .init(
        isChargingDesired: desired,
        overnightSafeChargingMinutes: 48,
        priceAllowsCharging: true,
        currentPriceDollarsPerKilowattHour: 0.24,
        batteryStateOfCharge: 78
      )
    )
  }
}

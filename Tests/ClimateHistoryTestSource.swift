import Foundation
import XCTest

@testable import Bruce

final class ClimateHistoryTestSource: HomeAssistantStateLoading, ClimateHistoryLoading,
  @unchecked Sendable
{
  let subscriptions = (0..<4).map { XCTestExpectation(description: "History subscription \($0)") }
  var subscribed: XCTestExpectation { subscriptions[0] }
  private var subscriptionCount = 0
  let terminated = XCTestExpectation(description: "History subscription released")
  let started = (0..<4).map { XCTestExpectation(description: "History request \($0)") }
  let returned = (0..<4).map { XCTestExpectation(description: "History returned \($0)") }
  private let lock = NSLock()
  private var continuation:
    HomeAssistantBufferedUpdateStream<HomeAssistantStateUpdate>.Continuation?
  private var requests: [Int: CheckedContinuation<ClimateHistory, any Error>] = [:]
  private var intervals: [DateInterval] = []
  var requestedIntervals: [DateInterval] { lock.withLock { intervals } }
  private var count = 0
  private var dateRead: XCTestExpectation?
  private var timestamp = Date(timeIntervalSince1970: 1_790_200_000)
  var requestCount: Int { lock.withLock { count } }
  var now: Date {
    lock.withLock {
      dateRead?.fulfill()
      dateRead = nil
      return timestamp
    }
  }

  func expectDateRead() -> XCTestExpectation {
    let expectation = XCTestExpectation(description: "Live update consumed")
    lock.withLock { dateRead = expectation }
    return expectation
  }

  func advance(_ seconds: Double) {
    lock.withLock { timestamp = timestamp.addingTimeInterval(seconds) }
  }

  func stateUpdates() async -> HomeAssistantBufferedUpdateStream<HomeAssistantStateUpdate> {
    HomeAssistantBufferedUpdateStream { continuation in
      lock.withLock { self.continuation = continuation }
      continuation.onTermination = { [terminated] _ in terminated.fulfill() }
      let index = lock.withLock {
        let index = subscriptionCount
        subscriptionCount += 1
        return index
      }
      subscriptions[index].fulfill()
    }
  }

  func loadClimateHistory(interval: DateInterval) async throws -> ClimateHistory {
    let index = lock.withLock {
      let index = count
      count += 1
      intervals.append(interval)
      return index
    }
    defer { returned[index].fulfill() }
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock { requests[index] = continuation }
      started[index].fulfill()
    }
  }

  func yield(_ update: HomeAssistantStateUpdate) {
    lock.withLock { continuation }?.yield(update)
  }

  func complete(_ index: Int, result: Result<ClimateHistory, any Error>) {
    lock.withLock { requests.removeValue(forKey: index) }?.resume(with: result)
  }

  func finish() {
    lock.withLock { continuation }?.finish()
    let pending = lock.withLock {
      let pending = requests.values
      requests = [:]
      return Array(pending)
    }
    for continuation in pending { continuation.resume(throwing: CancellationError()) }
  }

  func states(actual: Double = 24, system: String = "cool") throws -> [HomeAssistantState] {
    let data = Data(
      """
      [{"entity_id":"climate.ac_0","state":"\(system)","attributes":{}},
       {"entity_id":"climate.lounge","state":"fan_only","attributes":{"current_temperature":\(actual),"temperature":21}},
       {"entity_id":"cover.lounge_damper","state":"open","attributes":{"current_position":80}}]
      """.utf8)
    return try JSONDecoder().decode([HomeAssistantState].self, from: data)
  }

  func history() -> ClimateHistory {
    ClimateHistory(
      interval: DateInterval(start: now.addingTimeInterval(-12 * 3600), end: now), frames: [])
  }
}

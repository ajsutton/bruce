import Foundation
import XCTest

@testable import Bruce

final class ControlledConnectionClock: @unchecked Sendable {
  private struct Sleep {
    let id: UUID
    let duration: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private let lock = NSLock()
  private var instant: TimeInterval = 20_000
  private var sleeps: [Sleep] = []
  private var expectations: [Duration: [XCTestExpectation]] = [:]
  private var cancelledIDs: Set<UUID> = []

  var connectionClock: HomeAssistantConnectionClock {
    HomeAssistantConnectionClock(
      now: { self.lock.withLock { self.instant } },
      sleep: { duration, _ in try await self.sleep(for: duration) }
    )
  }

  func expectSleep(_ duration: Duration) -> XCTestExpectation {
    lock.withLock {
      let expectation = XCTestExpectation(description: "Sleep scheduled for \(duration)")
      if sleeps.contains(where: { $0.duration == duration }) {
        expectation.fulfill()
      } else {
        expectations[duration, default: []].append(expectation)
      }
      return expectation
    }
  }

  func resume(_ duration: Duration, advancingBy interval: TimeInterval) {
    let sleep = lock.withLock {
      guard let index = sleeps.firstIndex(where: { $0.duration == duration }) else {
        return Optional<Sleep>.none
      }
      instant += interval
      return sleeps.remove(at: index)
    }
    sleep?.continuation.resume()
  }

  private func sleep(for duration: Duration) async throws {
    guard duration != .zero else { return }
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let shouldCancel = lock.withLock {
          if cancelledIDs.remove(id) != nil { return true }
          sleeps.append(Sleep(id: id, duration: duration, continuation: continuation))
          expectations[duration]?.forEach { $0.fulfill() }
          expectations[duration] = nil
          return false
        }
        if shouldCancel { continuation.resume(throwing: CancellationError()) }
      }
    } onCancel: {
      self.cancel(id: id)
    }
  }

  private func cancel(id: UUID) {
    let continuation = lock.withLock {
      guard let index = sleeps.firstIndex(where: { $0.id == id }) else {
        cancelledIDs.insert(id)
        return Optional<CheckedContinuation<Void, any Error>>.none
      }
      return sleeps.remove(at: index).continuation
    }
    continuation?.resume(throwing: CancellationError())
  }
}

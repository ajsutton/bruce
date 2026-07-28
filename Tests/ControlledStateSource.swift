import Foundation
import XCTest

@testable import Bruce

final class ControlledStateSource:
  HomeAssistantStateLoading, @unchecked Sendable
{
  let started = XCTestExpectation(description: "State source started")
  let cancelled = XCTestExpectation(description: "State source cancelled")

  private let lock = NSLock()
  private var continuations:
    [Int: AsyncThrowingStream<HomeAssistantStateUpdate, any Error>.Continuation] = [:]
  private var storedSubscriptionCount = 0
  private var storedIsCancelled = false
  private var subscriptionExpectations: [Int: XCTestExpectation] = [:]

  var subscriptionCount: Int {
    lock.withLock { storedSubscriptionCount }
  }

  var isCancelled: Bool {
    lock.withLock { storedIsCancelled }
  }

  func stateUpdates() async -> AsyncThrowingStream<
    HomeAssistantStateUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      let state = lock.withLock {
        storedSubscriptionCount += 1
        let index = storedSubscriptionCount
        continuations[index] = continuation
        return (index, subscriptionExpectations.removeValue(forKey: index))
      }
      state.1?.fulfill()
      continuation.onTermination = { _ in
        self.lock.withLock {
          self.storedIsCancelled = true
        }
        self.cancelled.fulfill()
      }
      started.fulfill()
    }
  }

  func expectSubscriptionCount(_ count: Int) -> XCTestExpectation {
    let expectation = XCTestExpectation(
      description: "State source reached \(count) subscriptions"
    )
    let alreadyReached = lock.withLock {
      if storedSubscriptionCount >= count {
        return true
      }
      subscriptionExpectations[count] = expectation
      return false
    }
    if alreadyReached {
      expectation.fulfill()
    }
    return expectation
  }

  func yield(_ update: HomeAssistantStateUpdate, subscription: Int? = nil) {
    let continuation = lock.withLock {
      continuations[subscription ?? storedSubscriptionCount]
    }
    continuation?.yield(update)
  }

  func finish(throwing error: any Error, subscription: Int? = nil) {
    let continuation = lock.withLock {
      continuations[subscription ?? storedSubscriptionCount]
    }
    continuation?.finish(throwing: error)
  }
}

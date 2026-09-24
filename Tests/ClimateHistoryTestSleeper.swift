import Foundation
import XCTest

final class ClimateHistoryTestSleeper: @unchecked Sendable {
  let started = (0..<4).map { XCTestExpectation(description: "Sampling sleep \($0)") }
  let returned = (0..<4).map { XCTestExpectation(description: "Sampling resumed \($0)") }
  private let lock = NSLock()
  private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private var count = 0

  func sleep(_ duration: Duration) async {
    let index = lock.withLock {
      let index = count
      count += 1
      return index
    }
    await withCheckedContinuation { continuation in
      lock.withLock { continuations[index] = continuation }
      started[index].fulfill()
    }
    returned[index].fulfill()
  }

  func resume(_ index: Int) {
    lock.withLock { continuations.removeValue(forKey: index) }?.resume()
  }

  func finish() {
    let pending = lock.withLock {
      let pending = Array(continuations.values)
      continuations = [:]
      return pending
    }
    pending.forEach { $0.resume() }
  }
}

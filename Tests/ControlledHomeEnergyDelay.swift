import Foundation
import XCTest

final class ControlledHomeEnergyDelay: @unchecked Sendable {
  private let lock = NSLock()
  private let startedExpectations: [XCTestExpectation]
  private let completedExpectations: [XCTestExpectation]
  private var nextDelay = 0
  private var tokens: [Int: ControlledHomeEnergyDelayToken] = [:]

  init(delayCount: Int) {
    startedExpectations = (0..<delayCount).map {
      XCTestExpectation(description: "Home energy delay \($0) started")
    }
    completedExpectations = (0..<delayCount).map {
      XCTestExpectation(description: "Home energy delay \($0) completed")
    }
  }

  func started(at index: Int) -> XCTestExpectation {
    startedExpectations[index]
  }

  func completed(at index: Int) -> XCTestExpectation {
    completedExpectations[index]
  }

  func sleep(_ duration: Duration) async throws {
    let (index, token) = lock.withLock {
      let index = nextDelay
      nextDelay += 1
      let token = ControlledHomeEnergyDelayToken()
      tokens[index] = token
      return (index, token)
    }
    startedExpectations[index].fulfill()
    defer { completedExpectations[index].fulfill() }
    try await token.wait()
  }

  func finish(_ index: Int) {
    let token = lock.withLock {
      tokens.removeValue(forKey: index)
    }
    token?.finish()
  }
}

private final class ControlledHomeEnergyDelayToken: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, any Error>?
  private var isCancelled = false
  private var shouldFinish = false

  func wait() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let state = lock.withLock {
          if isCancelled {
            return DelayState.cancelled
          }
          if shouldFinish {
            return DelayState.finished
          }
          self.continuation = continuation
          return DelayState.waiting
        }
        switch state {
        case .cancelled:
          continuation.resume(throwing: CancellationError())
        case .finished:
          continuation.resume()
        case .waiting:
          break
        }
      }
    } onCancel: {
      cancel()
    }
  }

  func finish() {
    let continuation = lock.withLock {
      shouldFinish = true
      let continuation = continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume()
  }

  private func cancel() {
    let continuation = lock.withLock {
      isCancelled = true
      let continuation = continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(throwing: CancellationError())
  }
}

private enum DelayState {
  case cancelled
  case finished
  case waiting
}

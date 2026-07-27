import XCTest

@testable import Bruce

final class NonCooperativeClimateIconLoader:
  HomeAssistantClimateIconLoading, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Climate icon load started")

  private let lock = NSLock()
  private var continuation: UnsafeContinuation<[String: String], Never>?
  private var cancellationRequested = false
  private var storedLoadCount = 0

  var wasCancelled: Bool {
    lock.withLock { cancellationRequested }
  }

  var loadCount: Int {
    lock.withLock { storedLoadCount }
  }

  func loadClimateIcons() async throws -> [String: String] {
    await withTaskCancellationHandler {
      await withUnsafeContinuation { continuation in
        lock.withLock {
          storedLoadCount += 1
          self.continuation = continuation
        }
        started.fulfill()
      }
    } onCancel: {
      self.lock.withLock {
        self.cancellationRequested = true
      }
    }
  }

  func finish() {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(returning: [:])
  }
}

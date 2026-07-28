import Foundation
import XCTest

@testable import Bruce

final class ControlledHomeEnergyLoader:
  HomeAssistantHomeEnergyLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private let startedExpectations: [XCTestExpectation]
  private var nextRequest = 0
  private var continuations:
    [Int: CheckedContinuation<HomeAssistantHomeEnergySnapshot, any Error>] = [:]

  init(requestCount: Int) {
    startedExpectations = (0..<requestCount).map {
      XCTestExpectation(description: "Home energy load \($0) started")
    }
  }

  func started(at index: Int) -> XCTestExpectation {
    startedExpectations[index]
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    try await withCheckedThrowingContinuation { continuation in
      let request = lock.withLock {
        let request = nextRequest
        nextRequest += 1
        continuations[request] = continuation
        return request
      }
      startedExpectations[request].fulfill()
    }
  }

  func succeed(
    _ request: Int,
    with snapshot: HomeAssistantHomeEnergySnapshot
  ) {
    let continuation = lock.withLock {
      continuations.removeValue(forKey: request)
    }
    continuation?.resume(returning: snapshot)
  }
}

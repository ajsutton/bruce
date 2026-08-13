import Foundation
import XCTest

@testable import Bruce

final class OrderedBlockingHomeAssistantLoader:
  HomeAssistantHTTPDataLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private let startedExpectations: [XCTestExpectation]
  private var continuations: [Int: CheckedContinuation<(Data, HTTPURLResponse), any Error>] = [:]
  private var cancelledRequests: Set<Int> = []
  private var storedRequests: [URLRequest] = []

  init(requestCount: Int) {
    startedExpectations = (0..<requestCount).map {
      XCTestExpectation(description: "HTTP request \($0) started")
    }
  }

  var requests: [URLRequest] {
    lock.withLock { storedRequests }
  }

  func started(at index: Int) -> XCTestExpectation {
    startedExpectations[index]
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let index = lock.withLock {
      let index = storedRequests.count
      storedRequests.append(request)
      return index
    }
    guard startedExpectations.indices.contains(index) else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let wasCancelled = lock.withLock {
          if cancelledRequests.remove(index) != nil {
            return true
          }
          continuations[index] = continuation
          return false
        }
        startedExpectations[index].fulfill()
        if wasCancelled {
          continuation.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      self.cancel(request: index)
    }
  }

  func complete(request index: Int, data: Data, statusCode: Int) {
    let state = lock.withLock {
      (continuations.removeValue(forKey: index), storedRequests[index])
    }
    guard
      let response = HTTPURLResponse(
        url: state.1.url ?? URL(fileURLWithPath: "/"),
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      state.0?.resume(throwing: HomeAssistantAPIError.invalidResponse)
      return
    }
    state.0?.resume(returning: (data, response))
  }

  func complete(request index: Int, error: any Error) {
    lock.withLock { continuations.removeValue(forKey: index) }?.resume(throwing: error)
  }

  func cancelAll() {
    let pending = lock.withLock {
      let pending = Array(continuations.values)
      cancelledRequests.formUnion(storedRequests.indices)
      continuations.removeAll()
      return pending
    }
    pending.forEach { $0.resume(throwing: CancellationError()) }
  }

  private func cancel(request index: Int) {
    let continuation = lock.withLock {
      () -> CheckedContinuation<(Data, HTTPURLResponse), any Error>? in
      if let continuation = continuations.removeValue(forKey: index) {
        return continuation
      }
      cancelledRequests.insert(index)
      return nil
    }
    continuation?.resume(throwing: CancellationError())
  }
}

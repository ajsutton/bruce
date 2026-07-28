import Foundation

@testable import Bruce

final class RacingHomeAssistantLoader: HomeAssistantHTTPDataLoading, @unchecked Sendable {
  private let blockedHost: String
  private let successfulData: Data
  private let lock = NSLock()
  private var storedRequestedHosts: [String] = []
  private var blockedRouteCancellation = false
  private var blockedContinuation: CheckedContinuation<Void, any Error>?

  var requestedHosts: [String] {
    lock.withLock { storedRequestedHosts }
  }

  var wasBlockedRouteCancelled: Bool {
    lock.withLock { blockedRouteCancellation }
  }

  init(blockedHost: String, successfulData: Data) {
    self.blockedHost = blockedHost
    self.successfulData = successfulData
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let host = request.url?.host() ?? ""
    lock.withLock {
      storedRequestedHosts.append(host)
    }
    if host == blockedHost {
      try await waitForCancellation()
    }
    let responseURL = request.url ?? URL(fileURLWithPath: "/")
    guard
      let response = HTTPURLResponse(
        url: responseURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return (successfulData, response)
  }

  private func waitForCancellation() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let shouldCancel = lock.withLock {
          if blockedRouteCancellation {
            return true
          }
          blockedContinuation = continuation
          return false
        }
        if shouldCancel {
          continuation.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      let continuation = self.lock.withLock {
        self.blockedRouteCancellation = true
        let continuation = self.blockedContinuation
        self.blockedContinuation = nil
        return continuation
      }
      continuation?.resume(throwing: CancellationError())
    }
  }
}

import Foundation
import XCTest

@testable import Bruce

struct StubHomeAssistantWebSocketConnector: HomeAssistantWebSocketConnecting {
  let connection: StubHomeAssistantWebSocketConnection

  func connect(to url: URL) -> any HomeAssistantWebSocketConnection {
    connection.recordConnection(to: url)
    return connection
  }
}

final class StubHomeAssistantWebSocketConnection:
  HomeAssistantWebSocketConnection, @unchecked Sendable
{
  private let lock = NSLock()
  private var receivedMessages: [Data]
  private var sentMessages: [Data] = []
  private var storedConnectedURL: URL?
  private var cancellationRequested = false

  init(receivedMessages: [String]) {
    self.receivedMessages = receivedMessages.map { Data($0.utf8) }
  }

  var connectedURL: URL? {
    lock.withLock { storedConnectedURL }
  }

  var isCancelled: Bool {
    lock.withLock { cancellationRequested }
  }

  var sentMessageTypes: [String] {
    lock.withLock {
      sentMessages.compactMap { data in
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"]
          as? String
      }
    }
  }

  func recordConnection(to url: URL) {
    lock.withLock {
      storedConnectedURL = url
    }
  }

  func send(_ data: Data) async throws {
    lock.withLock {
      sentMessages.append(data)
    }
  }

  func receive() async throws -> Data {
    try lock.withLock {
      guard !receivedMessages.isEmpty else {
        throw HomeAssistantAPIError.invalidResponse
      }
      return receivedMessages.removeFirst()
    }
  }

  func cancel() {
    lock.withLock {
      cancellationRequested = true
    }
  }
}

struct BlockingHomeAssistantWebSocketConnector: HomeAssistantWebSocketConnecting {
  let connection: BlockingHomeAssistantWebSocketConnection

  func connect(to url: URL) -> any HomeAssistantWebSocketConnection {
    connection
  }
}

final class BlockingHomeAssistantWebSocketConnection:
  HomeAssistantWebSocketConnection, @unchecked Sendable
{
  let blockedReceiveStarted = XCTestExpectation(description: "WebSocket receive blocked")

  private let lock = NSLock()
  private var initialMessage: Data? = Data(#"{"type":"auth_required"}"#.utf8)
  private var continuation: CheckedContinuation<Data, any Error>?
  private var cancellationRequested = false

  var isCancelled: Bool {
    lock.withLock { cancellationRequested }
  }

  func send(_ data: Data) async throws {}

  func receive() async throws -> Data {
    if let initialMessage = lock.withLock({
      defer {
        self.initialMessage = nil
      }
      return self.initialMessage
    }) {
      return initialMessage
    }

    return try await withCheckedThrowingContinuation { continuation in
      let shouldCancel = lock.withLock {
        guard !cancellationRequested else {
          return true
        }
        self.continuation = continuation
        return false
      }
      if shouldCancel {
        continuation.resume(throwing: CancellationError())
      } else {
        blockedReceiveStarted.fulfill()
      }
    }
  }

  func cancel() {
    let continuation = lock.withLock {
      cancellationRequested = true
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(throwing: CancellationError())
  }
}

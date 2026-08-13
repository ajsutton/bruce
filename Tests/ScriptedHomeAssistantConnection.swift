import Foundation
import XCTest

@testable import Bruce

final class ScriptedHomeAssistantConnector:
  HomeAssistantWebSocketConnecting, @unchecked Sendable
{
  private let lock = NSLock()
  private var connections: [ScriptedHomeAssistantConnection]
  private var storedConnectionCount = 0
  private var storedConnectedURLs: [URL] = []

  init(connections: [ScriptedHomeAssistantConnection]) {
    self.connections = connections
  }

  var connectionCount: Int { lock.withLock { storedConnectionCount } }
  var connectedURLs: [URL] { lock.withLock { storedConnectedURLs } }

  func connect(to url: URL) -> any HomeAssistantWebSocketConnection {
    lock.withLock {
      storedConnectionCount += 1
      storedConnectedURLs.append(url)
      guard !connections.isEmpty else {
        return ScriptedHomeAssistantConnection(authenticationResponse: "auth_invalid")
      }
      return connections.removeFirst()
    }
  }
}

final class ScriptedHomeAssistantConnection:
  HomeAssistantWebSocketConnection, @unchecked Sendable
{
  let authenticationStarted = XCTestExpectation(description: "Authentication started")
  let pingStarted = XCTestExpectation(description: "Application heartbeat sent")
  let cancelled = XCTestExpectation(description: "Connection cancelled")
  private let lock = NSLock()
  private let authenticationResponse: String
  private let blocksAuthentication: Bool
  private let respondsToPing: Bool
  private let blocksCommands: Bool
  private let commandSendError: (any Error)?
  private var pendingAuthentication = false
  private var messages: [Result<Data, any Error>] = [
    .success(Data(#"{"type":"auth_required"}"#.utf8))
  ]
  private var continuation: CheckedContinuation<Data, any Error>?
  private var storedSubscriptionCount = 0
  private var storedPingCount = 0
  private var storedCommandIDs: [Int] = []
  private var commandExpectations: [Int: XCTestExpectation] = [:]
  private var cancellationRequested = false

  init(
    authenticationResponse: String = "auth_ok",
    initialReceiveError: (any Error)? = nil,
    blocksAuthentication: Bool = false,
    respondsToPing: Bool = true,
    blocksCommands: Bool = false,
    commandSendError: (any Error)? = nil
  ) {
    self.authenticationResponse = authenticationResponse
    self.blocksAuthentication = blocksAuthentication
    self.respondsToPing = respondsToPing
    self.blocksCommands = blocksCommands
    self.commandSendError = commandSendError
    if let initialReceiveError {
      messages = [.failure(initialReceiveError)]
    }
  }

  var subscriptionCount: Int { lock.withLock { storedSubscriptionCount } }
  var pingCount: Int { lock.withLock { storedPingCount } }
  var commandIDs: [Int] { lock.withLock { storedCommandIDs } }
  var isCancelled: Bool { lock.withLock { cancellationRequested } }

  func commandSent(at index: Int) -> XCTestExpectation {
    lock.withLock {
      let expectation = XCTestExpectation(description: "Command \(index) sent")
      commandExpectations[index] = expectation
      if storedCommandIDs.indices.contains(index) {
        expectation.fulfill()
      }
      return expectation
    }
  }

  func send(_ data: Data) async throws {
    guard
      let message = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = message["type"] as? String
    else { throw HomeAssistantAPIError.invalidResponse }
    switch type {
    case "auth":
      sendAuthentication()
    case "subscribe_events":
      try sendSubscription(message)
    case "ping":
      try sendPing(message)
    default:
      try sendCommand(message)
    }
  }

  private func sendAuthentication() {
    authenticationStarted.fulfill()
    if blocksAuthentication {
      lock.withLock { pendingAuthentication = true }
    } else {
      yield(#"{"type":"\#(authenticationResponse)"}"#)
    }
  }

  private func sendSubscription(_ message: [String: Any]) throws {
    guard let id = message["id"] as? Int else {
      throw HomeAssistantAPIError.invalidResponse
    }
    lock.withLock { storedSubscriptionCount += 1 }
    yield(#"{"id":\#(id),"type":"result","success":true,"result":null}"#)
  }

  private func sendPing(_ message: [String: Any]) throws {
    guard let id = message["id"] as? Int else {
      throw HomeAssistantAPIError.invalidResponse
    }
    lock.withLock { storedPingCount += 1 }
    pingStarted.fulfill()
    if respondsToPing {
      yield(#"{"id":\#(id),"type":"pong"}"#)
    }
  }

  private func sendCommand(_ message: [String: Any]) throws {
    guard let id = message["id"] as? Int else {
      throw HomeAssistantAPIError.invalidResponse
    }
    let expectation = lock.withLock {
      let index = storedCommandIDs.count
      storedCommandIDs.append(id)
      return commandExpectations[index]
    }
    expectation?.fulfill()
    if let commandSendError {
      throw commandSendError
    }
    if !blocksCommands {
      completeCommand(id: id)
    }
  }

  func receive() async throws -> Data {
    if let result = lock.withLock({ messages.isEmpty ? nil : messages.removeFirst() }) {
      return try result.get()
    }
    return try await withCheckedThrowingContinuation { continuation in
      let shouldCancel = lock.withLock {
        if cancellationRequested { return true }
        self.continuation = continuation
        return false
      }
      if shouldCancel { continuation.resume(throwing: CancellationError()) }
    }
  }

  func completeAuthentication() {
    let shouldComplete = lock.withLock {
      defer { pendingAuthentication = false }
      return pendingAuthentication
    }
    if shouldComplete {
      yield(#"{"type":"\#(authenticationResponse)"}"#)
    }
  }

  func completeCommand(
    id: Int,
    success: Bool = true,
    result: String = "null"
  ) {
    yield(
      #"{"id":\#(id),"type":"result","success":\#(success),"result":\#(result)}"#
    )
  }

  func yield(_ text: String) {
    resolve(.success(Data(text.utf8)))
  }

  func fail(with error: any Error) {
    resolve(.failure(error))
  }

  func cancel() {
    let continuation = lock.withLock {
      if !cancellationRequested { cancelled.fulfill() }
      cancellationRequested = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume(throwing: CancellationError())
  }

  private func resolve(_ result: Result<Data, any Error>) {
    let continuation = lock.withLock {
      guard let continuation else {
        messages.append(result)
        return Optional<CheckedContinuation<Data, any Error>>.none
      }
      self.continuation = nil
      return continuation
    }
    continuation?.resume(with: result)
  }
}

import Foundation
import XCTest

@testable import Bruce

struct TemperatureSubscriptionIconLoader: HomeAssistantClimateIconLoading {
  let icons: [String: String]

  func loadClimateIcons() async throws -> [String: String] {
    icons
  }
}

final class TemperatureSubscriptionConnector:
  HomeAssistantWebSocketConnecting, @unchecked Sendable
{
  private let lock = NSLock()
  private var connections: [TemperatureSubscriptionConnection]
  private var storedConnectedURLs: [URL] = []

  init(connections: [TemperatureSubscriptionConnection]) {
    self.connections = connections
  }

  var connectedURLs: [URL] {
    lock.withLock { storedConnectedURLs }
  }

  func connect(to url: URL) -> any HomeAssistantWebSocketConnection {
    lock.withLock {
      storedConnectedURLs.append(url)
      return connections.removeFirst()
    }
  }
}

final class TemperatureSubscriptionConnection:
  HomeAssistantWebSocketConnection, @unchecked Sendable
{
  enum Message {
    case success(String)
    case failure(any Error)
  }

  let blockedReceiveStarted = XCTestExpectation(
    description: "Temperature WebSocket receive blocked"
  )

  private let lock = NSLock()
  private var messages: [Message]
  private var sentMessages: [Data] = []
  private var continuation: CheckedContinuation<Data, any Error>?
  private var cancellationRequested = false
  private var reportedBlockedReceive = false

  init(messages: [Message]) {
    self.messages = messages
  }

  var sentMessageTypes: [String] {
    lock.withLock {
      sentMessages.compactMap { data in
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"]
          as? String
      }
    }
  }

  var isCancelled: Bool {
    lock.withLock { cancellationRequested }
  }

  func send(_ data: Data) async throws {
    lock.withLock {
      sentMessages.append(data)
    }
  }

  func receive() async throws -> Data {
    if let message = lock.withLock({ messages.isEmpty ? nil : messages.removeFirst() }) {
      switch message {
      case .success(let text):
        return Data(text.utf8)
      case .failure(let error):
        throw error
      }
    }

    return try await withCheckedThrowingContinuation { continuation in
      let state = lock.withLock {
        guard !cancellationRequested else {
          return (shouldCancel: true, shouldReportBlocked: false)
        }
        self.continuation = continuation
        let shouldReportBlocked = !reportedBlockedReceive
        reportedBlockedReceive = true
        return (shouldCancel: false, shouldReportBlocked: shouldReportBlocked)
      }
      if state.shouldCancel {
        continuation.resume(throwing: CancellationError())
      } else if state.shouldReportBlocked {
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

  func fail(with error: any Error) {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(throwing: error)
  }
}

final class RecordingSubscriptionSleeper: @unchecked Sendable {
  let started = XCTestExpectation(description: "Reconnect delay started")

  private let lock = NSLock()
  private let blocks: Bool
  private var storedDelays: [Duration] = []
  private var continuation: CheckedContinuation<Void, any Error>?

  init(blocks: Bool = false) {
    self.blocks = blocks
  }

  var delays: [Duration] {
    lock.withLock { storedDelays }
  }

  func sleep(for delay: Duration) async throws {
    lock.withLock {
      storedDelays.append(delay)
    }
    guard blocks else {
      return
    }
    try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func resume() {
    resolve(.success(()))
  }

  func cancel() {
    resolve(.failure(CancellationError()))
  }

  private func resolve(_ result: Result<Void, any Error>) {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(with: result)
  }
}

func makeClient(
  session: HomeAssistantSession,
  connections: [TemperatureSubscriptionConnection],
  icons: [String: String] = [:],
  retryDelays: [Duration] = [],
  sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
) -> HomeAssistantTemperatureStream {
  HomeAssistantTemperatureStream(
    session: session,
    apiClient: HomeAssistantAPIClient(
      session: session,
      climateIconLoader: TemperatureSubscriptionIconLoader(icons: icons)
    ),
    connector: TemperatureSubscriptionConnector(connections: connections),
    retryDelays: retryDelays,
    sleep: sleep
  )
}

func snapshot(
  from update: HomeAssistantTemperatureUpdate?
) throws -> [HomeAssistantTemperatureReading] {
  switch try XCTUnwrap(update) {
  case .live(let readings):
    return readings
  case .reconnecting:
    throw HomeAssistantAPIError.invalidResponse
  }
}

func temperatureResponses(values: [Double]) -> [QueueHomeAssistantLoader.Result] {
  values.flatMap { value in
    [
      .success(
        Data(#"{"unit_system":{"temperature":"°C"}}"#.utf8),
        statusCode: 200
      ),
      .success(temperatureStates(value: value), statusCode: 200),
    ]
  }
}

func temperatureStates(value: Double) -> Data {
  Data(
    #"""
    [{
      "entity_id": "climate.bedroom",
      "state": "cool",
      "attributes": {
        "current_temperature": \#(value),
        "friendly_name": "Bedroom"
      },
      "last_updated": "2026-07-27T01:02:03Z"
    }]
    """#.utf8
  )
}

func stateChangedEvent(entityID: String, value: Double?) -> String {
  let currentTemperature = value.map { String($0) } ?? "null"
  return
    #"""
    {
      "id": 1,
      "type": "event",
      "event": {
        "event_type": "state_changed",
        "data": {
          "entity_id": "\#(entityID)",
          "new_state": {
            "entity_id": "\#(entityID)",
            "state": "cool",
            "attributes": {
              "current_temperature": \#(currentTemperature),
              "friendly_name": "Bedroom"
            },
            "last_updated": "2026-07-27T01:03:04Z"
          }
        }
      }
    }
    """#
}

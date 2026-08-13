import Foundation
import XCTest

@testable import Bruce

struct TemperatureSubscriptionMetadataLoader: HomeAssistantClimateMetadataLoading {
  let metadata: [String: HomeAssistantClimateMetadata]

  func loadClimateMetadata() async throws -> [String: HomeAssistantClimateMetadata] {
    metadata
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

  var sentMessageJSON: [[String: Any]] {
    lock.withLock {
      sentMessages.compactMap {
        try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
      }
    }
  }

  var isCancelled: Bool {
    lock.withLock { cancellationRequested }
  }

  func send(_ data: Data) async throws {
    let response: (CheckedContinuation<Data, any Error>, Data)? = lock.withLock {
      sentMessages.append(data)
      guard
        let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        message["type"] as? String == "subscribe_events",
        let id = message["id"] as? Int,
        id > 1
      else { return nil }
      let response = #"{"id":\#(id),"type":"result","success":true,"result":null}"#
      let data = Data(response.utf8)
      if let continuation {
        self.continuation = nil
        return (continuation, data)
      }
      messages.insert(.success(response), at: 0)
      return nil
    }
    if let response {
      response.0.resume(returning: response.1)
    }
  }

  func receive() async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let state = lock.withLock {
        if !messages.isEmpty {
          return (
            message: Optional(messages.removeFirst()),
            shouldCancel: false,
            shouldReportBlocked: false
          )
        }
        guard !cancellationRequested else {
          return (
            message: Optional<Message>.none,
            shouldCancel: true,
            shouldReportBlocked: false
          )
        }
        self.continuation = continuation
        let shouldReportBlocked = !reportedBlockedReceive
        reportedBlockedReceive = true
        return (
          message: Optional<Message>.none,
          shouldCancel: false,
          shouldReportBlocked: shouldReportBlocked
        )
      }
      if let message = state.message {
        switch message {
        case .success(let text):
          continuation.resume(returning: Data(text.utf8))
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      } else if state.shouldCancel {
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

  func succeed(with message: String) {
    let continuation = lock.withLock {
      guard let continuation = self.continuation else {
        messages.append(.success(message))
        return Optional<CheckedContinuation<Data, any Error>>.none
      }
      self.continuation = nil
      return continuation
    }
    continuation?.resume(returning: Data(message.utf8))
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

func snapshot(
  from update: HomeAssistantTemperatureUpdate?
) throws -> [HomeAssistantTemperatureReading] {
  switch try XCTUnwrap(update) {
  case .live(let readings):
    return readings
  case .refreshing, .reconnecting, .unavailable:
    throw HomeAssistantAPIError.invalidResponse
  }
}

func temperatureResponses(
  values: [Double],
  units: [String]? = nil
) -> [QueueHomeAssistantLoader.Result] {
  let units = units ?? Array(repeating: "°C", count: values.count)
  return zip(values, units).flatMap { value, unit in
    [
      .success(temperatureStates(value: value), statusCode: 200),
      .success(
        Data(#"{"unit_system":{"temperature":"\#(unit)"}}"#.utf8),
        statusCode: 200
      ),
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
        "temperature": \#(value + 1),
        "friendly_name": "Bedroom"
      },
      "last_updated": "2026-07-27T01:02:03Z"
    }]
    """#.utf8
  )
}

func stateChangedEvent(
  entityID: String,
  value: Double?,
  state: String = "cool",
  target: Double? = nil
) -> String {
  let currentTemperature = value.map { String($0) } ?? "null"
  let targetTemperature = target.map { String($0) } ?? "null"
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
            "state": "\#(state)",
            "attributes": {
              "current_temperature": \#(currentTemperature),
              "temperature": \#(targetTemperature),
              "friendly_name": "Bedroom"
            },
            "last_updated": "2026-07-27T01:03:04Z"
          },
          "old_state": null
        }
      }
    }
    """#
}

func stateRemovedEvent(entityID: String, oldLastUpdated: String) -> String {
  #"""
  {
    "id": 1,
    "type": "event",
    "event": {
      "event_type": "state_changed",
      "data": {
        "entity_id": "\#(entityID)",
        "new_state": null,
        "old_state": {
          "entity_id": "\#(entityID)",
          "state": "cool",
          "attributes": {
            "current_temperature": 20,
            "friendly_name": "Bedroom"
          },
          "last_updated": "\#(oldLastUpdated)"
        }
      }
    }
  }
  """#
}

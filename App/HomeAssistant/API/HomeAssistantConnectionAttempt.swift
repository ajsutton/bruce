import Foundation

actor HomeAssistantConnectionAttempt {
  private typealias ResponseContinuation = CheckedContinuation<Data, any Error>

  private enum ResponseState {
    case awaiting(ResponseContinuation?)
    case buffered(Result<Data, any Error>)
    case abandoned
  }

  private static let maximumAbandonedResponseCount = 64

  nonisolated let id: UUID
  nonisolated let authenticationSessionEpoch: Int
  nonisolated let routeCategory: String

  private let now: @Sendable () -> TimeInterval
  private var nextCommandID = 1
  private var responseStates: [Int: ResponseState] = [:]
  private var abandonedResponseCount = 0
  private var bufferedEvents: [String: Data] = [:]
  private var isPublishingEvents = false
  private var eventBuffer: HomeAssistantConnectionEventBuffer?
  private(set) var lastInboundMessageAt: TimeInterval
  private var isFinished = false
  private var finishError: (any Error)?

  init(
    id: UUID,
    authenticationSessionEpoch: Int,
    routeCategory: String,
    now: @escaping @Sendable () -> TimeInterval
  ) {
    self.id = id
    self.authenticationSessionEpoch = authenticationSessionEpoch
    self.routeCategory = routeCategory
    self.now = now
    lastInboundMessageAt = now()
  }

  func allocateCommandID() throws -> Int {
    try ensureActive()
    defer { nextCommandID += 1 }
    responseStates[nextCommandID] = .awaiting(nil)
    return nextCommandID
  }

  func receive(_ data: Data) async throws {
    guard !isFinished else { return }
    let envelope: HomeAssistantWebSocketEnvelope
    do {
      envelope = try JSONDecoder().decode(HomeAssistantWebSocketEnvelope.self, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }
    lastInboundMessageAt = now()
    switch envelope.type {
    case "result", "pong":
      guard let id = envelope.id else { throw HomeAssistantAPIError.invalidResponse }
      try resolveResponse(id: id, result: .success(data))
    case "event":
      if isPublishingEvents {
        guard let eventBuffer else { throw CancellationError() }
        try Task.checkCancellation()
        try await eventBuffer.yield(data)
      } else {
        let event = try JSONDecoder().decode(HomeAssistantBufferedEvent.self, from: data)
        bufferedEvents[event.coalescingKey] = data
      }
    default:
      throw HomeAssistantAPIError.invalidResponse
    }
  }

  func response(for commandID: Int) async throws -> Data {
    guard !Task.isCancelled else {
      cancelResponse(commandID)
      throw CancellationError()
    }
    try ensureActive()
    guard let responseState = responseStates[commandID] else {
      throw HomeAssistantAPIError.invalidResponse
    }
    switch responseState {
    case .buffered(let result):
      responseStates.removeValue(forKey: commandID)
      try Task.checkCancellation()
      return try result.get()
    case .awaiting:
      break
    case .abandoned:
      throw HomeAssistantAPIError.invalidResponse
    }
    let data: Data = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: ResponseContinuation) in
        responseStates[commandID] = .awaiting(continuation)
        if Task.isCancelled { cancelResponse(commandID) }
      }
    } onCancel: {
      Task { await self.cancelResponse(commandID) }
    }
    try Task.checkCancellation()
    return data
  }

  private func cancelResponse(_ commandID: Int) {
    guard let responseState = responseStates[commandID] else { return }
    switch responseState {
    case .awaiting(let continuation):
      responseStates[commandID] = .abandoned
      abandonedResponseCount += 1
      continuation?.resume(throwing: CancellationError())
      guard abandonedResponseCount <= Self.maximumAbandonedResponseCount else {
        finish(throwing: HomeAssistantAPIError.invalidResponse)
        return
      }
    case .buffered:
      // The command is already complete. Retire it without granting a future response allowance.
      responseStates.removeValue(forKey: commandID)
    case .abandoned:
      break
    }
  }

  func beginPublishingEvents() throws -> (
    buffered: [Data],
    stream: HomeAssistantConnectionEventSequence
  ) {
    try ensureActive()
    let eventBuffer = HomeAssistantConnectionEventBuffer()
    self.eventBuffer = eventBuffer
    let stream = HomeAssistantConnectionEventSequence(buffer: eventBuffer)
    isPublishingEvents = true
    let buffered = Array(bufferedEvents.values)
    bufferedEvents = [:]
    return (buffered, stream)
  }

  func finish(throwing error: (any Error)? = nil) {
    guard !isFinished else { return }
    isFinished = true
    finishError = error
    var continuations: [ResponseContinuation] = []
    for responseState in responseStates.values {
      if case .awaiting(let continuation) = responseState, let continuation {
        continuations.append(continuation)
      }
    }
    responseStates = [:]
    abandonedResponseCount = 0
    for continuation in continuations {
      continuation.resume(throwing: error ?? CancellationError())
    }
    let finishingEventBuffer = eventBuffer
    if let error {
      Task { await finishingEventBuffer?.finish(throwing: error) }
    } else {
      Task { await finishingEventBuffer?.finish() }
    }
    eventBuffer = nil
    bufferedEvents = [:]
  }

  private func resolveResponse(
    id: Int,
    result: Result<Data, any Error>
  ) throws {
    guard let responseState = responseStates[id] else {
      throw HomeAssistantAPIError.invalidResponse
    }
    switch responseState {
    case .awaiting(let continuation):
      if let continuation {
        responseStates.removeValue(forKey: id)
        continuation.resume(with: result)
      } else {
        responseStates[id] = .buffered(result)
      }
    case .buffered:
      throw HomeAssistantAPIError.invalidResponse
    case .abandoned:
      responseStates.removeValue(forKey: id)
      abandonedResponseCount -= 1
    }
  }

  private func ensureActive() throws {
    guard !isFinished else { throw finishError ?? CancellationError() }
  }
}

private struct HomeAssistantWebSocketEnvelope: Decodable {
  let id: Int?
  let type: String
}

struct HomeAssistantBufferedEvent: Decodable {
  let id: Int
  let event: HomeAssistantBufferedEventEnvelope

  var coalescingKey: String {
    event.data?.entityID.map { "event:\(event.eventType):entity:\($0)" }
      ?? "event:\(event.eventType):subscription:\(id)"
  }
}

struct HomeAssistantBufferedEventEnvelope: Decodable {
  let eventType: String
  let data: HomeAssistantBufferedEventData?

  enum CodingKeys: String, CodingKey {
    case eventType = "event_type"
    case data
  }
}

struct HomeAssistantBufferedEventData: Decodable {
  let entityID: String?

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
  }
}

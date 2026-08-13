import Foundation

struct HomeAssistantConnectionEventSequence: AsyncSequence, Sendable {
  typealias Element = Data

  struct AsyncIterator: AsyncIteratorProtocol {
    let buffer: HomeAssistantConnectionEventBuffer

    mutating func next() async throws -> Data? {
      try await buffer.next()
    }
  }

  let buffer: HomeAssistantConnectionEventBuffer

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(buffer: buffer)
  }
}

actor HomeAssistantConnectionEventBuffer {
  private typealias Waiter = CheckedContinuation<Data?, any Error>

  private var events: [String: Data] = [:]
  private var order: [String] = []
  private var waiter: Waiter?
  private var terminalError: (any Error)?
  private var isFinished = false

  func yield(_ data: Data) throws {
    guard !isFinished else { return }
    if let waiter {
      self.waiter = nil
      waiter.resume(returning: data)
      return
    }
    let key = try HomeAssistantConnectionEventKey.key(for: data)
    if events[key] == nil { order.append(key) }
    events[key] = data
  }

  func next() async throws -> Data? {
    if !order.isEmpty {
      let key = order.removeFirst()
      return events.removeValue(forKey: key)
    }
    if isFinished {
      if let terminalError { throw terminalError }
      return nil
    }
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { waiter = $0 }
    } onCancel: {
      Task { await self.finish(throwing: CancellationError()) }
    }
  }

  func finish(throwing error: (any Error)? = nil) {
    guard !isFinished else { return }
    isFinished = true
    terminalError = error
    events = [:]
    order = []
    let waiter = waiter
    self.waiter = nil
    if let error {
      waiter?.resume(throwing: error)
    } else {
      waiter?.resume(returning: nil)
    }
  }
}

private enum HomeAssistantConnectionEventKey {
  static func key(for data: Data) throws -> String {
    let event = try JSONDecoder().decode(HomeAssistantBufferedEvent.self, from: data)
    return event.coalescingKey
  }
}

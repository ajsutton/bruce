import Foundation

protocol HomeAssistantWebSocketConnection: Sendable {
  func send(_ data: Data) async throws
  func receive() async throws -> Data
  func ping() async throws
  func cancel()
}

extension HomeAssistantWebSocketConnection {
  func ping() async throws {}
}

protocol HomeAssistantWebSocketConnecting: Sendable {
  func connect(to url: URL) -> any HomeAssistantWebSocketConnection
}

struct URLSessionWebSocketConnector: HomeAssistantWebSocketConnecting {
  private let session: URLSession

  init(session: URLSession? = nil) {
    self.session =
      session
      ?? URLSession(
        configuration: URLSessionHomeAssistantHTTPDataLoader.makeConfiguration(),
        delegate: HomeAssistantRedirectDelegate(),
        delegateQueue: nil
      )
  }

  func connect(to url: URL) -> any HomeAssistantWebSocketConnection {
    URLSessionWebSocketConnection(task: session.webSocketTask(with: url))
  }
}

private final class URLSessionWebSocketConnection:
  HomeAssistantWebSocketConnection, @unchecked Sendable
{
  private let task: URLSessionWebSocketTask

  init(task: URLSessionWebSocketTask) {
    self.task = task
    task.resume()
  }

  func send(_ data: Data) async throws {
    guard let text = String(data: data, encoding: .utf8) else {
      throw HomeAssistantAPIError.invalidResponse
    }
    try await task.send(.string(text))
  }

  func receive() async throws -> Data {
    switch try await task.receive() {
    case .data(let data):
      return data
    case .string(let text):
      return Data(text.utf8)
    @unknown default:
      throw HomeAssistantAPIError.invalidResponse
    }
  }

  func ping() async throws {
    let completion = HomeAssistantWebSocketPingCompletion()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        completion.install(continuation)
        task.sendPing { error in
          completion.resolve(
            error.map { .failure($0) } ?? .success(())
          )
        }
        Task {
          try? await Task.sleep(for: .seconds(10))
          if completion.resolve(.failure(URLError(.timedOut))) {
            task.cancel(with: .goingAway, reason: nil)
          }
        }
      }
    } onCancel: {
      if completion.resolve(.failure(CancellationError())) {
        task.cancel(with: .goingAway, reason: nil)
      }
    }
  }

  func cancel() {
    task.cancel(with: .goingAway, reason: nil)
  }
}

private final class HomeAssistantWebSocketPingCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, any Error>?
  private var pendingResult: Result<Void, any Error>?

  func install(_ continuation: CheckedContinuation<Void, any Error>) {
    let result: Result<Void, any Error>? = lock.withLock {
      if let pendingResult {
        return pendingResult
      }
      self.continuation = continuation
      return nil
    }
    if let result {
      continuation.resume(with: result)
    }
  }

  @discardableResult
  func resolve(_ result: Result<Void, any Error>) -> Bool {
    let continuation: CheckedContinuation<Void, any Error>? = lock.withLock {
      guard case nil = pendingResult else { return nil }
      pendingResult = result
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(with: result)
    return continuation != nil
  }
}

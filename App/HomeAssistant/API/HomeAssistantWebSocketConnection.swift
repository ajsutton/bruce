import Foundation

protocol HomeAssistantWebSocketConnection: Sendable {
  func send(_ data: Data) async throws
  func receive() async throws -> Data
  func cancel()
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

  func cancel() {
    task.cancel(with: .goingAway, reason: nil)
  }
}

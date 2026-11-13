import Foundation

@MainActor
final class OpenClawGateway: OpenClawRequesting {
  private struct Pending {
    let continuation: CheckedContinuation<OpenClawWireValue, any Error>
    let timeout: Task<Void, Never>
    var sender: Task<Void, Never>?
  }

  private let session: URLSession
  private var socket: URLSessionWebSocketTask?
  private var receiver: Task<Void, Never>?
  private var heartbeat: Task<Void, Never>?
  private var pending: [String: Pending] = [:]
  var onTalkEvent: ((OpenClawTalkEvent) -> Void)?
  var onDisconnect: (() -> Void)?

  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    session = URLSession(configuration: configuration)
  }

  func connect(access: CloudflareAccessSession, identity: OpenClawDeviceIdentity) async throws {
    close()
    var components = URLComponents(url: access.origin.url, resolvingAgainstBaseURL: false)
    components?.scheme = "wss"
    guard let url = components?.url, let token = access.authorizationHeader(for: url) else {
      throw OpenClawVoiceError.signInRequired
    }
    var request = URLRequest(url: url)
    request.setValue(token, forHTTPHeaderField: "Cf-Access-Token")
    request.setValue(CloudflareAccessClient.userAgent, forHTTPHeaderField: "User-Agent")
    let socket = session.webSocketTask(with: request)
    socket.maximumMessageSize = 26_214_400
    self.socket = socket
    socket.resume()
    let deadline = Task {
      do {
        try await Task.sleep(for: .seconds(30))
        socket.cancel(with: .goingAway, reason: nil)
      } catch { return }
    }
    defer { deadline.cancel() }
    do {
      let challenge = try await withTaskCancellationHandler {
        try await Self.receive(socket)
      } onCancel: {
        socket.cancel(with: .goingAway, reason: nil)
      }
      guard challenge["event"]?.string == "connect.challenge", let payload = challenge["payload"]
      else {
        throw OpenClawVoiceError.protocolFailure
      }
      beginReceiving(socket)
      _ = try await call("connect", parameters: identity.connectParameters(challenge: payload))
      try Task.checkCancellation()
      beginHeartbeat(socket)
    } catch {
      close()
      throw error
    }
  }

  private func beginReceiving(_ socket: URLSessionWebSocketTask) {
    receiver = Task { [weak self] in
      do {
        while !Task.isCancelled {
          let frame = try await Self.receive(socket)
          self?.accept(frame)
        }
      } catch {
        guard !Task.isCancelled, self?.socket === socket else { return }
        self?.close()
        self?.onDisconnect?()
      }
    }
  }

  private func beginHeartbeat(_ socket: URLSessionWebSocketTask) {
    heartbeat = Task { [weak self] in
      do {
        while !Task.isCancelled {
          try await Task.sleep(for: .seconds(15))
          socket.sendPing { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor [weak self] in
              guard self?.socket === socket else { return }
              self?.close()
              self?.onDisconnect?()
            }
          }
        }
      } catch { return }
    }
  }

  func call(
    _ method: String, parameters: OpenClawWireValue = .object([:]),
    retainingReplyOnCancellation: Bool = false
  ) async throws
    -> OpenClawWireValue
  {
    guard let socket else { throw OpenClawVoiceError.disconnected }
    try Task.checkCancellation()
    let id = UUID().uuidString
    let request = OpenClawWireValue.object([
      "type": .string("req"), "id": .string(id), "method": .string(method), "params": parameters,
    ])
    let data = try JSONEncoder().encode(request)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let timeout = Task { [weak self] in
          do { try await Task.sleep(for: .seconds(30)) } catch { return }
          if retainingReplyOnCancellation {
            self?.close()
          } else {
            self?.complete(id, result: .failure(URLError(.timedOut)))
          }
        }
        pending[id] = Pending(continuation: continuation, timeout: timeout, sender: nil)
        let sender = Task { [weak self] in
          guard self?.pending[id] != nil, !Task.isCancelled else { return }
          do { try await socket.send(.data(data)) } catch {
            self?.complete(id, result: .failure(error))
          }
        }
        pending[id]?.sender = sender
      }
    } onCancel: {
      guard !retainingReplyOnCancellation else { return }
      Task { @MainActor [weak self] in self?.complete(id, result: .failure(CancellationError())) }
    }
  }

  func close() {
    receiver?.cancel()
    receiver = nil
    heartbeat?.cancel()
    heartbeat = nil
    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    let requests = pending
    pending = [:]
    for request in requests.values {
      request.timeout.cancel()
      request.sender?.cancel()
      request.continuation.resume(throwing: OpenClawVoiceError.disconnected)
    }
  }

  private func accept(_ frame: OpenClawWireValue) {
    if frame["event"]?.string == "talk.event", let payload = frame["payload"] {
      // Relay sessions use another envelope and cannot own this WebRTC call.
      guard payload["voiceSessionId"]?.string != nil else { return }
      do { onTalkEvent?(try payload.decode(OpenClawTalkEvent.self)) } catch {
        close()
        onDisconnect?()
      }
      return
    }
    guard frame["type"]?.string == "res", let id = frame["id"]?.string else { return }
    if case .bool(true) = frame["ok"] {
      complete(id, result: .success(frame["payload"] ?? .null))
    } else {
      complete(
        id, result: .failure(OpenClawVoiceError.gateway(frame["error"]?["message"]?.string ?? "")))
    }
  }

  private func complete(_ id: String, result: Result<OpenClawWireValue, any Error>) {
    guard let request = pending.removeValue(forKey: id) else { return }
    request.timeout.cancel()
    request.sender?.cancel()
    request.continuation.resume(with: result)
  }

  private static func receive(_ socket: URLSessionWebSocketTask) async throws -> OpenClawWireValue {
    let data: Data
    switch try await socket.receive() {
    case .data(let value): data = value
    case .string(let value): data = Data(value.utf8)
    @unknown default: throw OpenClawVoiceError.protocolFailure
    }
    return try JSONDecoder().decode(OpenClawWireValue.self, from: data)
  }
}

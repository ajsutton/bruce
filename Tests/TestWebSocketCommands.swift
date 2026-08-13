import Foundation

@testable import Bruce

actor TestWebSocketCommands: HomeAssistantWebSocketCommanding {
  private let session: HomeAssistantSession
  private let connector: any HomeAssistantWebSocketConnecting
  private let connectionBox = TestWebSocketConnectionBox()
  private var connection: (any HomeAssistantWebSocketConnection)?
  private var nextID = 1

  init(session: HomeAssistantSession, connector: any HomeAssistantWebSocketConnecting) {
    self.session = session
    self.connector = connector
  }

  func perform(_ command: HomeAssistantWebSocketCommand) async throws -> Data {
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      let connection = try await authenticatedConnection()
      let id = nextID
      nextID += 1
      try await connection.send(command.data(id: id))
      return try await connection.receive()
    } onCancel: {
      self.connectionBox.cancel()
    }
  }

  private func authenticatedConnection() async throws -> any HomeAssistantWebSocketConnection {
    if let connection { return connection }
    let access = try await session.authenticatedWebSocketAccess()
    let connection = connector.connect(to: access.url)
    connectionBox.store(connection)
    self.connection = connection
    let required = try await connection.receive()
    guard try messageType(required) == "auth_required" else {
      throw HomeAssistantAPIError.invalidResponse
    }
    try await connection.send(
      JSONSerialization.data(withJSONObject: ["type": "auth", "access_token": access.accessToken])
    )
    let response = try await connection.receive()
    switch try messageType(response) {
    case "auth_ok": return connection
    case "auth_invalid":
      connection.cancel()
      throw HomeAssistantAPIError.unauthorized
    default:
      connection.cancel()
      throw HomeAssistantAPIError.invalidResponse
    }
  }

  private func messageType(_ data: Data) throws -> String? {
    (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String
  }
}

private final class TestWebSocketConnectionBox: @unchecked Sendable {
  private let lock = NSLock()
  private var connection: (any HomeAssistantWebSocketConnection)?

  func store(_ connection: any HomeAssistantWebSocketConnection) {
    lock.withLock { self.connection = connection }
  }

  func cancel() {
    lock.withLock { connection }?.cancel()
  }
}

import Foundation

protocol HomeAssistantClimateIconLoading: Sendable {
  func loadClimateIcons() async throws -> [String: String]
}

struct HomeAssistantRegistryClient: HomeAssistantClimateIconLoading {
  private let session: HomeAssistantSession
  private let connector: any HomeAssistantWebSocketConnecting

  init(
    session: HomeAssistantSession,
    connector: any HomeAssistantWebSocketConnecting =
      URLSessionWebSocketConnector()
  ) {
    self.session = session
    self.connector = connector
  }

  func loadClimateIcons() async throws -> [String: String] {
    let access = try await session.authenticatedWebSocketAccess()
    let connection = connector.connect(to: access.url)
    return try await withTaskCancellationHandler {
      defer {
        connection.cancel()
      }
      try await authenticate(connection, accessToken: access.accessToken)
      let entities: [HomeAssistantRegistryEntity] = try await request(
        "config/entity_registry/list",
        id: 1,
        over: connection
      )
      let devices: [HomeAssistantRegistryDevice] = try await request(
        "config/device_registry/list",
        id: 2,
        over: connection
      )
      let areas: [HomeAssistantRegistryArea] = try await request(
        "config/area_registry/list",
        id: 3,
        over: connection
      )
      try Task.checkCancellation()
      return Self.climateIcons(entities: entities, devices: devices, areas: areas)
    } onCancel: {
      connection.cancel()
    }
  }

  static func climateIcons(
    entities: [HomeAssistantRegistryEntity],
    devices: [HomeAssistantRegistryDevice],
    areas: [HomeAssistantRegistryArea]
  ) -> [String: String] {
    let devicesByID = devices.reduce(into: [:]) { devicesByID, device in
      devicesByID[device.id] = device
    }
    let areasByID = areas.reduce(into: [:]) { areasByID, area in
      areasByID[area.id] = area
    }

    return entities.reduce(into: [:]) { icons, entity in
      guard entity.id.hasPrefix("climate.") else {
        return
      }
      let areaID = entity.areaID ?? entity.deviceID.flatMap { devicesByID[$0]?.areaID }
      let areaIcon = areaID.flatMap { areasByID[$0]?.icon }
      if let icon = entity.icon ?? areaIcon ?? entity.originalIcon {
        icons[entity.id] = icon
      }
    }
  }

  private func authenticate(
    _ connection: any HomeAssistantWebSocketConnection,
    accessToken: String
  ) async throws {
    let required = try decode(
      HomeAssistantWebSocketMessageKind.self,
      from: try await connection.receive()
    )
    guard required.type == "auth_required" else {
      throw HomeAssistantAPIError.invalidResponse
    }

    try await send(
      HomeAssistantWebSocketAuthentication(type: "auth", accessToken: accessToken),
      over: connection
    )
    let authentication = try decode(
      HomeAssistantWebSocketMessageKind.self,
      from: try await connection.receive()
    )
    guard authentication.type == "auth_ok" else {
      if authentication.type == "auth_invalid" {
        throw HomeAssistantAPIError.unauthorized
      }
      throw HomeAssistantAPIError.invalidResponse
    }
  }

  private func request<Result: Decodable>(
    _ type: String,
    id: Int,
    over connection: any HomeAssistantWebSocketConnection
  ) async throws -> Result {
    try await send(
      HomeAssistantWebSocketRequest(id: id, type: type),
      over: connection
    )
    let response = try decode(
      HomeAssistantWebSocketResult<Result>.self,
      from: try await connection.receive()
    )
    guard response.id == id, response.type == "result", response.success,
      let result = response.result
    else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return result
  }

  private func send<Message: Encodable>(
    _ message: Message,
    over connection: any HomeAssistantWebSocketConnection
  ) async throws {
    try await connection.send(JSONEncoder().encode(message))
  }

  private func decode<Message: Decodable>(
    _ type: Message.Type,
    from data: Data
  ) throws -> Message {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }
  }
}

struct HomeAssistantRegistryEntity: Decodable, Equatable, Sendable {
  let id: String
  let deviceID: String?
  let areaID: String?
  let icon: String?
  let originalIcon: String?

  enum CodingKeys: String, CodingKey {
    case id = "entity_id"
    case deviceID = "device_id"
    case areaID = "area_id"
    case icon
    case originalIcon = "original_icon"
  }
}

struct HomeAssistantRegistryDevice: Decodable, Equatable, Sendable {
  let id: String
  let areaID: String?

  enum CodingKeys: String, CodingKey {
    case id
    case areaID = "area_id"
  }
}

struct HomeAssistantRegistryArea: Decodable, Equatable, Sendable {
  let id: String
  let icon: String?

  enum CodingKeys: String, CodingKey {
    case id = "area_id"
    case icon
  }
}

private struct HomeAssistantWebSocketMessageKind: Decodable {
  let type: String
}

private struct HomeAssistantWebSocketAuthentication: Encodable {
  let type: String
  let accessToken: String

  enum CodingKeys: String, CodingKey {
    case type
    case accessToken = "access_token"
  }
}

private struct HomeAssistantWebSocketRequest: Encodable {
  let id: Int
  let type: String
}

private struct HomeAssistantWebSocketResult<Result: Decodable>: Decodable {
  let id: Int
  let type: String
  let success: Bool
  let result: Result?
}

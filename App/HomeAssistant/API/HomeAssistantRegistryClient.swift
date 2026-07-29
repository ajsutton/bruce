import Foundation

protocol HomeAssistantClimateMetadataLoading: Sendable {
  func loadClimateMetadata() async throws -> [String: HomeAssistantClimateMetadata]
}

protocol HomeAssistantGarageDoorRegistryLoading: Sendable {
  func loadGarageDoorRegistry() async throws -> HomeAssistantGarageDoorRegistry
}

struct HomeAssistantClimateMetadata: Equatable, Sendable {
  let icon: String?
  let kind: HomeAssistantTemperatureReading.Kind
}

struct HomeAssistantRegistryClient:
  HomeAssistantClimateMetadataLoading, HomeAssistantGarageDoorRegistryLoading
{
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

  func loadClimateMetadata() async throws -> [String: HomeAssistantClimateMetadata] {
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
      return Self.climateMetadata(entities: entities, devices: devices, areas: areas)
    } onCancel: {
      connection.cancel()
    }
  }

  func loadGarageDoorRegistry() async throws -> HomeAssistantGarageDoorRegistry {
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
      try Task.checkCancellation()
      return Self.garageDoorRegistry(entities: entities, devices: devices)
    } onCancel: {
      connection.cancel()
    }
  }

  static func garageDoorRegistry(
    entities: [HomeAssistantRegistryEntity],
    devices: [HomeAssistantRegistryDevice]
  ) -> HomeAssistantGarageDoorRegistry {
    HomeAssistantGarageDoorRegistry(
      deviceIDByEntityID: entities.reduce(into: [:]) { result, entity in
        guard let deviceID = entity.deviceID else { return }
        result[entity.id] = deviceID
      },
      deviceNameByID: devices.reduce(into: [:]) { result, device in
        guard let name = device.nameByUser ?? device.name else { return }
        result[device.id] = name
      }
    )
  }

  static func climateMetadata(
    entities: [HomeAssistantRegistryEntity],
    devices: [HomeAssistantRegistryDevice],
    areas: [HomeAssistantRegistryArea]
  ) -> [String: HomeAssistantClimateMetadata] {
    let devicesByID = devices.reduce(into: [:]) { devicesByID, device in
      devicesByID[device.id] = device
    }
    let areasByID = areas.reduce(into: [:]) { areasByID, area in
      areasByID[area.id] = area
    }

    return entities.reduce(into: [:]) { metadata, entity in
      guard entity.id.hasPrefix("climate.") else {
        return
      }
      let areaID = entity.areaID ?? entity.deviceID.flatMap { devicesByID[$0]?.areaID }
      let areaIcon = areaID.flatMap { areasByID[$0]?.icon }
      metadata[entity.id] = HomeAssistantClimateMetadata(
        icon: entity.icon ?? areaIcon ?? entity.originalIcon,
        kind: kind(for: entity)
      )
    }
  }

  private static func kind(
    for entity: HomeAssistantRegistryEntity
  ) -> HomeAssistantTemperatureReading.Kind {
    guard entity.platform == "airtouch5", let uniqueID = entity.uniqueID else {
      return .other
    }
    if identifier(uniqueID, hasPrefix: "ac_") {
      return .airConditioner
    }
    if identifier(uniqueID, hasPrefix: "zone_") {
      return .zone
    }
    return .other
  }

  private static func identifier(_ identifier: String, hasPrefix prefix: String) -> Bool {
    guard identifier.hasPrefix(prefix) else {
      return false
    }
    return Int(identifier.dropFirst(prefix.count)) != nil
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
  let platform: String?
  let uniqueID: String?
  let deviceID: String?
  let areaID: String?
  let icon: String?
  let originalIcon: String?

  init(
    id: String,
    platform: String? = nil,
    uniqueID: String? = nil,
    deviceID: String?,
    areaID: String?,
    icon: String?,
    originalIcon: String?
  ) {
    self.id = id
    self.platform = platform
    self.uniqueID = uniqueID
    self.deviceID = deviceID
    self.areaID = areaID
    self.icon = icon
    self.originalIcon = originalIcon
  }

  enum CodingKeys: String, CodingKey {
    case id = "entity_id"
    case platform
    case uniqueID = "unique_id"
    case deviceID = "device_id"
    case areaID = "area_id"
    case icon
    case originalIcon = "original_icon"
  }
}

struct HomeAssistantRegistryDevice: Decodable, Equatable, Sendable {
  let id: String
  let areaID: String?
  let name: String?
  let nameByUser: String?

  init(
    id: String,
    areaID: String?,
    name: String? = nil,
    nameByUser: String? = nil
  ) {
    self.id = id
    self.areaID = areaID
    self.name = name
    self.nameByUser = nameByUser
  }

  enum CodingKeys: String, CodingKey {
    case id
    case areaID = "area_id"
    case name
    case nameByUser = "name_by_user"
  }
}

struct HomeAssistantGarageDoorRegistry: Equatable, Sendable {
  let deviceIDByEntityID: [String: String]
  let deviceNameByID: [String: String]
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

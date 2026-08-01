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
  let floor: HomeAssistantClimateFloor?
  let presetLabels: [HomeAssistantClimatePresetLabel]

  init(
    icon: String?,
    kind: HomeAssistantTemperatureReading.Kind,
    floor: HomeAssistantClimateFloor? = nil,
    presetLabels: [HomeAssistantClimatePresetLabel] = []
  ) {
    self.icon = icon
    self.kind = kind
    self.floor = floor
    self.presetLabels = presetLabels
  }
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
      let floors: [HomeAssistantRegistryFloor] = try await request(
        "config/floor_registry/list",
        id: 4,
        over: connection
      )
      let labels: [HomeAssistantRegistryLabel] = try await request(
        "config/label_registry/list",
        id: 5,
        over: connection
      )
      try Task.checkCancellation()
      return Self.climateMetadata(
        entities: entities,
        devices: devices,
        areas: areas,
        floors: floors,
        labels: labels
      )
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
    areas: [HomeAssistantRegistryArea],
    floors: [HomeAssistantRegistryFloor] = [],
    labels: [HomeAssistantRegistryLabel] = []
  ) -> [String: HomeAssistantClimateMetadata] {
    let devicesByID = devices.reduce(into: [:]) { devicesByID, device in
      devicesByID[device.id] = device
    }
    let areasByID = areas.reduce(into: [:]) { areasByID, area in
      areasByID[area.id] = area
    }
    let floorsByID = floors.reduce(into: [:]) { floorsByID, floor in
      floorsByID[floor.id] = floor
    }
    let labelsByID = labels.reduce(into: [:]) { labelsByID, label in
      labelsByID[label.id] = label
    }

    return entities.reduce(into: [:]) { metadata, entity in
      guard entity.id.hasPrefix("climate.") else {
        return
      }
      let areaID = entity.areaID ?? entity.deviceID.flatMap { devicesByID[$0]?.areaID }
      let registryArea = areaID.flatMap { areasByID[$0] }
      let registryFloor = registryArea?.floorID.flatMap { floorsByID[$0] }
      let deviceLabelIDs = entity.deviceID.flatMap { devicesByID[$0]?.labelIDs } ?? []
      let presetLabels = climatePresetLabels(
        labelIDs: Set(entity.labelIDs + deviceLabelIDs + (registryArea?.labelIDs ?? [])),
        labelsByID: labelsByID
      )
      metadata[entity.id] = HomeAssistantClimateMetadata(
        icon: entity.icon ?? registryArea?.icon ?? entity.originalIcon,
        kind: kind(for: entity),
        floor: registryFloor.map {
          HomeAssistantClimateFloor(id: $0.id, name: $0.name, level: $0.level)
        },
        presetLabels: presetLabels
      )
    }
  }

  private static func climatePresetLabels(
    labelIDs: Set<String>,
    labelsByID: [String: HomeAssistantRegistryLabel]
  ) -> [HomeAssistantClimatePresetLabel] {
    labelIDs.compactMap { id in
      guard let label = labelsByID[id], label.name.hasPrefix(climatePresetLabelPrefix) else {
        return nil
      }
      let name = label.name
        .dropFirst(climatePresetLabelPrefix.count)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { return nil }
      return HomeAssistantClimatePresetLabel(id: id, name: name)
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private static let climatePresetLabelPrefix = "Climate preset:"

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

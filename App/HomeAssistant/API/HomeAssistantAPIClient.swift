import Foundation

struct HomeAssistantAPIStatus: Decodable, Equatable, Sendable {
  let message: String
}

struct HomeAssistantAPIClient: Sendable {
  private let session: HomeAssistantSession

  init(session: HomeAssistantSession) {
    self.session = session
  }

  func checkConnection() async throws -> HomeAssistantAPIStatus {
    let data = try await session.authenticatedGET(path: "api/")
    return try Self.status(from: data)
  }

  func loadTemperatures() async throws -> [HomeAssistantTemperatureReading] {
    let configurationData = try await session.authenticatedGET(path: "api/config")
    try Task.checkCancellation()
    let unit = try Self.temperatureUnit(from: configurationData)
    try Task.checkCancellation()
    let statesData = try await session.authenticatedGET(path: "api/states")
    try Task.checkCancellation()
    return try Self.temperatures(from: statesData, unit: unit)
  }

  static func status(from data: Data) throws -> HomeAssistantAPIStatus {
    guard
      let status = try? JSONDecoder().decode(HomeAssistantAPIStatus.self, from: data),
      status.message == "API running."
    else {
      throw HomeAssistantAPIError.incompatibleServer
    }
    return status
  }

  static func temperatureUnit(from data: Data) throws -> String {
    do {
      return try JSONDecoder().decode(HomeAssistantAPIConfiguration.self, from: data)
        .unitSystem.temperature
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }
  }

  static func temperatures(
    from data: Data,
    unit: String
  ) throws -> [HomeAssistantTemperatureReading] {
    let states: [HomeAssistantState]
    do {
      states = try JSONDecoder().decode([HomeAssistantState].self, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }
    return states.compactMap { $0.temperatureReading(unit: unit) }.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}

extension HomeAssistantAPIClient: HomeAssistantTemperatureLoading {}

private struct HomeAssistantAPIConfiguration: Decodable {
  let unitSystem: HomeAssistantUnitSystem

  enum CodingKeys: String, CodingKey {
    case unitSystem = "unit_system"
  }
}

private struct HomeAssistantUnitSystem: Decodable {
  let temperature: String
}

private struct HomeAssistantState: Decodable {
  let entityID: String
  let attributes: HomeAssistantStateAttributes
  let lastUpdated: String?

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case attributes
    case lastUpdated = "last_updated"
  }

  func temperatureReading(unit: String) -> HomeAssistantTemperatureReading? {
    guard
      entityID.hasPrefix("climate."),
      let value = attributes.currentTemperature,
      value.isFinite
    else {
      return nil
    }
    return HomeAssistantTemperatureReading(
      id: entityID,
      name: attributes.friendlyName ?? fallbackName,
      value: value,
      unit: unit,
      updatedAt: parsedLastUpdated,
      icon: attributes.icon
    )
  }

  private var fallbackName: String {
    let objectID = entityID.split(separator: ".", maxSplits: 1).last.map(String.init) ?? entityID
    return objectID.replacingOccurrences(of: "_", with: " ").localizedCapitalized
  }

  private var parsedLastUpdated: Date? {
    guard let lastUpdated else {
      return nil
    }
    if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(lastUpdated)
    {
      return date
    }
    return try? Date.ISO8601FormatStyle().parse(lastUpdated)
  }
}

private struct HomeAssistantStateAttributes: Decodable {
  let currentTemperature: Double?
  let friendlyName: String?
  let icon: String?

  enum CodingKeys: String, CodingKey {
    case currentTemperature = "current_temperature"
    case friendlyName = "friendly_name"
    case icon
  }
}

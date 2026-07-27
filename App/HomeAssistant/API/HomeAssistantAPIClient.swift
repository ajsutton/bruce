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
    let data = try await session.authenticatedGET(path: "api/states")
    return try Self.temperatures(from: data)
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

  static func temperatures(from data: Data) throws -> [HomeAssistantTemperatureReading] {
    let states: [HomeAssistantState]
    do {
      states = try JSONDecoder().decode([HomeAssistantState].self, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }
    return states.compactMap(\.temperatureReading).sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}

extension HomeAssistantAPIClient: HomeAssistantTemperatureLoading {}

private struct HomeAssistantState: Decodable {
  let entityID: String
  let state: String
  let attributes: HomeAssistantStateAttributes
  let lastUpdated: String?

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case state
    case attributes
    case lastUpdated = "last_updated"
  }

  var temperatureReading: HomeAssistantTemperatureReading? {
    guard
      attributes.deviceClass == "temperature",
      let value = Double(state),
      value.isFinite
    else {
      return nil
    }
    return HomeAssistantTemperatureReading(
      id: entityID,
      name: attributes.friendlyName ?? fallbackName,
      value: value,
      unit: attributes.unitOfMeasurement,
      updatedAt: parsedLastUpdated
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
  let deviceClass: String?
  let friendlyName: String?
  let unitOfMeasurement: String?

  enum CodingKeys: String, CodingKey {
    case deviceClass = "device_class"
    case friendlyName = "friendly_name"
    case unitOfMeasurement = "unit_of_measurement"
  }
}

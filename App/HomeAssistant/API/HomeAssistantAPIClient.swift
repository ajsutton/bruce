import Foundation
import OSLog

struct HomeAssistantAPIStatus: Decodable, Equatable, Sendable {
  let message: String
}

struct HomeAssistantTemperatureSnapshot: Sendable {
  let readings: [HomeAssistantTemperatureReading]
  let unit: String
  let climateIcons: [String: String]
}

struct HomeAssistantAPIClient: Sendable {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.symphonious.bruce",
    category: "HomeAssistantAPI"
  )

  private let session: HomeAssistantSession
  private let climateIconLoader: any HomeAssistantClimateIconLoading
  private let climateIconTimeout: Duration
  private let climateIconCoordinator: HomeAssistantClimateIconLoadCoordinator

  init(session: HomeAssistantSession) {
    self.session = session
    climateIconLoader = HomeAssistantRegistryClient(session: session)
    climateIconTimeout = .seconds(2)
    climateIconCoordinator = HomeAssistantClimateIconLoadCoordinator()
  }

  init(
    session: HomeAssistantSession,
    climateIconLoader: any HomeAssistantClimateIconLoading,
    climateIconTimeout: Duration = .seconds(2)
  ) {
    self.session = session
    self.climateIconLoader = climateIconLoader
    self.climateIconTimeout = climateIconTimeout
    climateIconCoordinator = HomeAssistantClimateIconLoadCoordinator()
  }

  func checkConnection() async throws -> HomeAssistantAPIStatus {
    let data = try await session.authenticatedGET(path: "api/")
    return try Self.status(from: data)
  }

  func loadTemperatures() async throws -> [HomeAssistantTemperatureReading] {
    try await loadTemperatureSnapshot().readings
  }

  func loadTemperatureSnapshot() async throws -> HomeAssistantTemperatureSnapshot {
    let configurationData = try await session.authenticatedGET(path: "api/config")
    try Task.checkCancellation()
    let unit = try Self.temperatureUnit(from: configurationData)
    try Task.checkCancellation()
    let statesData = try await session.authenticatedGET(path: "api/states")
    try Task.checkCancellation()
    let climateIcons = try await loadClimateIcons()
    try Task.checkCancellation()
    return try HomeAssistantTemperatureSnapshot(
      readings: Self.temperatures(
        from: statesData,
        unit: unit,
        climateIcons: climateIcons
      ),
      unit: unit,
      climateIcons: climateIcons
    )
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
    unit: String,
    climateIcons: [String: String] = [:]
  ) throws -> [HomeAssistantTemperatureReading] {
    let states: [HomeAssistantState]
    do {
      states = try JSONDecoder().decode([HomeAssistantState].self, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }
    return states.compactMap {
      $0.temperatureReading(unit: unit, registryIcon: climateIcons[$0.entityID])
    }.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  private func loadClimateIcons() async throws -> [String: String] {
    try await climateIconCoordinator.load(timeout: climateIconTimeout) {
      do {
        return try await climateIconLoader.loadClimateIcons()
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        Self.logger.error(
          "Couldn’t load Home Assistant room icons: \(String(describing: error), privacy: .private)"
        )
        return [:]
      }
    }
  }
}

private struct HomeAssistantAPIConfiguration: Decodable {
  let unitSystem: HomeAssistantUnitSystem

  enum CodingKeys: String, CodingKey {
    case unitSystem = "unit_system"
  }
}

private struct HomeAssistantUnitSystem: Decodable {
  let temperature: String
}

struct HomeAssistantState: Decodable {
  let entityID: String
  private let state: String
  private let attributes: HomeAssistantStateAttributes

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case state
    case attributes
  }

  func temperatureReading(
    unit: String,
    registryIcon: String?
  ) -> HomeAssistantTemperatureReading? {
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
      targetValue: finiteTargetTemperature,
      unit: unit,
      powerState: powerState,
      icon: attributes.icon ?? registryIcon
    )
  }

  private var fallbackName: String {
    let objectID = entityID.split(separator: ".", maxSplits: 1).last.map(String.init) ?? entityID
    return objectID.replacingOccurrences(of: "_", with: " ").localizedCapitalized
  }

  private var finiteTargetTemperature: Double? {
    guard let targetTemperature = attributes.targetTemperature, targetTemperature.isFinite else {
      return nil
    }
    return targetTemperature
  }

  private var powerState: HomeAssistantTemperatureReading.PowerState {
    switch state {
    case "off":
      .off
    case "unavailable", "unknown":
      .unavailable
    default:
      .poweredOn
    }
  }
}

private struct HomeAssistantStateAttributes: Decodable {
  let currentTemperature: Double?
  let targetTemperature: Double?
  let friendlyName: String?
  let icon: String?

  enum CodingKeys: String, CodingKey {
    case currentTemperature = "current_temperature"
    case targetTemperature = "temperature"
    case friendlyName = "friendly_name"
    case icon
  }
}

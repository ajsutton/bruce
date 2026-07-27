import Foundation
import OSLog

struct HomeAssistantAPIStatus: Decodable, Equatable, Sendable {
  let message: String
}

struct HomeAssistantTemperatureSnapshot: Sendable {
  let readings: [HomeAssistantTemperatureReading]
  let unit: String
  let climateMetadata: [String: HomeAssistantClimateMetadata]
}

protocol HomeAssistantClimateControlling: Sendable {
  func setPower(entityID: String, isOn: Bool) async throws
  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) async throws
}

struct HomeAssistantAPIClient: HomeAssistantClimateControlling, Sendable {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.symphonious.bruce",
    category: "HomeAssistantAPI"
  )

  private let session: HomeAssistantSession
  private let climateMetadataLoader: any HomeAssistantClimateMetadataLoading
  private let climateMetadataTimeout: Duration
  private let climateMetadataCoordinator: ClimateMetadataLoadCoordinator

  init(session: HomeAssistantSession) {
    self.session = session
    climateMetadataLoader = HomeAssistantRegistryClient(session: session)
    climateMetadataTimeout = .seconds(2)
    climateMetadataCoordinator = ClimateMetadataLoadCoordinator()
  }

  init(
    session: HomeAssistantSession,
    climateMetadataLoader: any HomeAssistantClimateMetadataLoading,
    climateMetadataTimeout: Duration = .seconds(2)
  ) {
    self.session = session
    self.climateMetadataLoader = climateMetadataLoader
    self.climateMetadataTimeout = climateMetadataTimeout
    climateMetadataCoordinator = ClimateMetadataLoadCoordinator()
  }

  func checkConnection() async throws -> HomeAssistantAPIStatus {
    let data = try await session.authenticatedGET(path: "api/")
    return try Self.status(from: data)
  }

  func setPower(entityID: String, isOn: Bool) async throws {
    let service = isOn ? "turn_on" : "turn_off"
    let body = try JSONEncoder().encode(HomeAssistantClimateTarget(entityID: entityID))
    _ = try await session.authenticatedPOST(
      path: "api/services/climate/\(service)",
      body: body
    )
  }

  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) async throws {
    let body = try JSONEncoder().encode(
      HomeAssistantClimateModeRequest(entityID: entityID, mode: mode.rawValue)
    )
    _ = try await session.authenticatedPOST(
      path: "api/services/climate/set_hvac_mode",
      body: body
    )
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
    let climateMetadata = try await loadClimateMetadata()
    try Task.checkCancellation()
    return try HomeAssistantTemperatureSnapshot(
      readings: Self.temperatures(
        from: statesData,
        unit: unit,
        climateMetadata: climateMetadata
      ),
      unit: unit,
      climateMetadata: climateMetadata
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
    climateMetadata: [String: HomeAssistantClimateMetadata] = [:]
  ) throws -> [HomeAssistantTemperatureReading] {
    let states: [HomeAssistantState]
    do {
      states = try JSONDecoder().decode([HomeAssistantState].self, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }
    return states.compactMap {
      $0.temperatureReading(unit: unit, metadata: climateMetadata[$0.entityID])
    }.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  private func loadClimateMetadata() async throws -> [String: HomeAssistantClimateMetadata] {
    try await climateMetadataCoordinator.load(timeout: climateMetadataTimeout) {
      do {
        return try await climateMetadataLoader.loadClimateMetadata()
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        Self.logger.error(
          "Couldn’t load Home Assistant climate metadata: \(String(describing: error), privacy: .private)"
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
    metadata: HomeAssistantClimateMetadata?
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
      kind: metadata?.kind ?? .other,
      operatingMode: operatingMode,
      availableModes: availableModes,
      icon: attributes.icon ?? metadata?.icon
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

  private var operatingMode: HomeAssistantTemperatureReading.OperatingMode {
    switch state {
    case "auto", "heat_cool":
      .automatic
    case "cool":
      .cooling
    case "dry":
      .drying
    case "fan_only":
      .fanOnly
    case "heat":
      .heating
    case "off":
      .off
    case "unavailable", "unknown":
      .unavailable
    default:
      .active
    }
  }

  private var availableModes: [HomeAssistantTemperatureReading.ClimateMode] {
    attributes.hvacModes?.compactMap(
      HomeAssistantTemperatureReading.ClimateMode.init(rawValue:)
    ) ?? []
  }

}

private struct HomeAssistantStateAttributes: Decodable {
  let currentTemperature: Double?
  let targetTemperature: Double?
  let friendlyName: String?
  let icon: String?
  let hvacModes: [String]?

  enum CodingKeys: String, CodingKey {
    case currentTemperature = "current_temperature"
    case targetTemperature = "temperature"
    case friendlyName = "friendly_name"
    case icon
    case hvacModes = "hvac_modes"
  }
}

private struct HomeAssistantClimateTarget: Encodable {
  let entityID: String

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
  }
}

private struct HomeAssistantClimateModeRequest: Encodable {
  let entityID: String
  let mode: String

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case mode = "hvac_mode"
  }
}

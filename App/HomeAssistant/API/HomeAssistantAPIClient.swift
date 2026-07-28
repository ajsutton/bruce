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
  func setTargetValue(_ value: Double, entityID: String) async throws
  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) async throws
}

struct HomeAssistantAPIClient:
  HomeAssistantClimateControlling, HomeAssistantEVCharging,
  HomeAssistantHomeEnergyLoading, Sendable
{
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
    let data = try await session.checkConnection { data in
      _ = try Self.status(from: data)
    }
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

  func setTargetValue(_ value: Double, entityID: String) async throws {
    let body = try JSONEncoder().encode(
      HomeAssistantClimateTemperatureRequest(entityID: entityID, temperature: value)
    )
    _ = try await session.authenticatedPOST(
      path: "api/services/climate/set_temperature",
      body: body
    )
  }

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    let data = try await session.authenticatedGET(
      path: "api/states/input_select.ev_charging_mode"
    )
    return try Self.evChargingMode(from: data)
  }

  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    let data = try await session.authenticatedGET(path: "api/states")
    return try HomeAssistantEVChargingSnapshot(homeAssistantStates: data)
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    let data = try await session.authenticatedGET(path: "api/states")
    return try HomeAssistantHomeEnergySnapshot(homeAssistantStates: data)
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    let body = try JSONEncoder().encode(
      HomeAssistantSelectOptionRequest(
        entityID: "input_select.ev_charging_mode",
        option: mode.rawValue
      )
    )
    _ = try await session.authenticatedPOST(
      path: "api/services/input_select/select_option",
      body: body
    )
    return try await loadEVChargingMode()
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

  static func evChargingMode(from data: Data) throws -> HomeAssistantEVChargingMode {
    do {
      let state = try JSONDecoder().decode(HomeAssistantEVChargingState.self, from: data)
      guard let mode = HomeAssistantEVChargingMode(rawValue: state.state) else {
        throw HomeAssistantAPIError.invalidResponse
      }
      return mode
    } catch let error as HomeAssistantAPIError {
      throw error
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
  let state: String
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
      icon: attributes.icon ?? metadata?.icon,
      minimumTargetValue: attributes.minimumTemperature,
      maximumTargetValue: attributes.maximumTemperature,
      targetValueStep: attributes.targetTemperatureStep ?? attributes.temperaturePrecision
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
  let minimumTemperature: Double?
  let maximumTemperature: Double?
  let targetTemperatureStep: Double?
  let temperaturePrecision: Double?

  enum CodingKeys: String, CodingKey {
    case currentTemperature = "current_temperature"
    case targetTemperature = "temperature"
    case friendlyName = "friendly_name"
    case icon
    case hvacModes = "hvac_modes"
    case minimumTemperature = "min_temp"
    case maximumTemperature = "max_temp"
    case targetTemperatureStep = "target_temp_step"
    case temperaturePrecision = "precision"
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

private struct HomeAssistantClimateTemperatureRequest: Encodable {
  let entityID: String
  let temperature: Double

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case temperature
  }
}

private struct HomeAssistantEVChargingState: Decodable {
  let state: String
}

private struct HomeAssistantSelectOptionRequest: Encodable {
  let entityID: String
  let option: String

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case option
  }
}

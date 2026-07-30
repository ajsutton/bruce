import Foundation
import OSLog

struct HomeAssistantAPIClient:
  HomeAssistantClimateControlling, HomeAssistantEVCharging,
  HomeAssistantHomeEnergyLoading, HomeAssistantGarageDoorControlling, Sendable
{
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.symphonious.bruce",
    category: "HomeAssistantAPI"
  )

  private let session: HomeAssistantSession
  private let climateMetadataLoader: any HomeAssistantClimateMetadataLoading
  private let climateMetadataTimeout: Duration
  private let climateMetadataCoordinator: ClimateMetadataLoadCoordinator
  private let now: @Sendable () -> Date

  init(
    session: HomeAssistantSession,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.session = session
    climateMetadataLoader = HomeAssistantRegistryClient(session: session)
    climateMetadataTimeout = .seconds(2)
    climateMetadataCoordinator = ClimateMetadataLoadCoordinator()
    self.now = now
  }

  init(
    session: HomeAssistantSession,
    climateMetadataLoader: any HomeAssistantClimateMetadataLoading,
    climateMetadataTimeout: Duration = .seconds(2),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.session = session
    self.climateMetadataLoader = climateMetadataLoader
    self.climateMetadataTimeout = climateMetadataTimeout
    climateMetadataCoordinator = ClimateMetadataLoadCoordinator()
    self.now = now
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
    let states = try await loadHomeAssistantStates()
    return try Self.evChargingMode(from: states)
  }

  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    let states = try await loadHomeAssistantStates()
    return try HomeAssistantEVChargingSnapshot(states: states)
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(states: try await loadHomeAssistantStates())
  }

  func loadHomeEnergyPriceHistory() async throws -> HomeEnergyPriceHistory {
    let end = now()
    let start = end.addingTimeInterval(-24 * 60 * 60)
    let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    let data = try await session.authenticatedGET(
      path: "api/history/period/\(start.formatted(timestampStyle))",
      queryItems: [
        URLQueryItem(name: "end_time", value: end.formatted(timestampStyle)),
        URLQueryItem(
          name: "filter_entity_id",
          value: [
            HomeAssistantHomeEnergySnapshot.generalPriceEntityID,
            HomeAssistantHomeEnergySnapshot.feedInPriceEntityID,
          ].joined(separator: ",")
        ),
        URLQueryItem(name: "minimal_response", value: nil),
        URLQueryItem(name: "no_attributes", value: nil),
      ]
    )
    return try HomeEnergyPriceHistory(
      data: data,
      interval: DateInterval(start: start, end: end)
    )
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    let states = try await loadHomeAssistantStates()
    guard let modeEntity = HomeAssistantEVChargingSnapshot.modeEntity(in: states) else {
      throw HomeAssistantAPIError.invalidResponse
    }
    let body = try JSONEncoder().encode(
      HomeAssistantSelectOptionRequest(
        entityID: modeEntity.entityID,
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
    let context = try await loadTemperatureContext()
    let states = try await loadHomeAssistantStates()
    return HomeAssistantTemperatureSnapshot(
      readings: Self.temperatureReadings(
        from: states,
        context: context
      ),
      unit: context.unit,
      climateMetadata: context.climateMetadata
    )
  }

  func loadHomeAssistantStates() async throws -> [HomeAssistantState] {
    let data = try await session.authenticatedGET(path: "api/states")
    do {
      let states = try JSONDecoder().decode([HomeAssistantState].self, from: data)
      guard Set(states.map(\.entityID)).count == states.count else {
        throw HomeAssistantAPIError.invalidResponse
      }
      return states
    } catch let error as HomeAssistantAPIError {
      throw error
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }
  }

  func loadTemperatureContext() async throws -> HomeAssistantTemperatureContext {
    let configurationData = try await session.authenticatedGET(path: "api/config")
    try Task.checkCancellation()
    let unit = try Self.temperatureUnit(from: configurationData)
    try Task.checkCancellation()
    let climateMetadata = try await loadClimateMetadata()
    try Task.checkCancellation()
    return HomeAssistantTemperatureContext(
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

  static func evChargingMode(
    from states: [HomeAssistantState]
  ) throws -> HomeAssistantEVChargingMode {
    guard
      let state = HomeAssistantEVChargingSnapshot.modeEntity(in: states),
      let mode = HomeAssistantEVChargingMode(rawValue: state.state)
    else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return mode
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
    return temperatureReadings(
      from: states,
      context: HomeAssistantTemperatureContext(
        unit: unit,
        climateMetadata: climateMetadata
      )
    )
  }

  static func temperatureReadings(
    from states: [HomeAssistantState],
    context: HomeAssistantTemperatureContext
  ) -> [HomeAssistantTemperatureReading] {
    states.compactMap {
      $0.temperatureReading(
        unit: context.unit,
        metadata: context.climateMetadata[$0.entityID]
      )
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

extension HomeAssistantAPIClient {
  func setGarageLight(entityID: String, isOn: Bool) async throws {
    try await callEntityService(
      domain: "light",
      service: isOn ? "turn_on" : "turn_off",
      entityID: entityID
    )
  }

  func setGarageLock(entityID: String, isLocked: Bool) async throws {
    try await callEntityService(
      domain: "lock",
      service: isLocked ? "lock" : "unlock",
      entityID: entityID
    )
  }

  func sendGarageDoorCommand(
    _ command: HomeAssistantGarageDoorCommand,
    entityID: String
  ) async throws {
    let service =
      switch command {
      case .open: "open_cover"
      case .close: "close_cover"
      case .stop: "stop_cover"
      }
    try await callEntityService(
      domain: "cover",
      service: service,
      entityID: entityID
    )
  }

  private func callEntityService(
    domain: String,
    service: String,
    entityID: String
  ) async throws {
    let body = try JSONEncoder().encode(HomeAssistantEntityTarget(entityID: entityID))
    _ = try await session.authenticatedPOST(
      path: "api/services/\(domain)/\(service)",
      body: body
    )
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

private struct HomeAssistantClimateTarget: Encodable {
  let entityID: String

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
  }
}

private struct HomeAssistantEntityTarget: Encodable {
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

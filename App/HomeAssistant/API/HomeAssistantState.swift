import Foundation

struct HomeAssistantState: Decodable, Equatable, Sendable {
  let entityID: String
  let state: String
  let lastUpdated: Date?
  private let attributes: HomeAssistantStateAttributes

  var deviceClass: String? { attributes.deviceClass }
  var friendlyName: String? { attributes.friendlyName }
  var icon: String? { attributes.icon }
  var options: [String] { attributes.options ?? [] }
  var unitOfMeasurement: String? { attributes.unitOfMeasurement }
  var currentPosition: Double? { attributes.currentPosition }
  var supportedFeatures: Int { attributes.supportedFeatures ?? 0 }
  var isAvailable: Bool {
    state != "unavailable" && state != "unknown"
  }

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case state
    case attributes
    case lastUpdated = "last_updated"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    entityID = try container.decode(String.self, forKey: .entityID)
    state = try container.decode(String.self, forKey: .state)
    attributes = try container.decode(HomeAssistantStateAttributes.self, forKey: .attributes)
    guard let value = try container.decodeIfPresent(String.self, forKey: .lastUpdated) else {
      lastUpdated = nil
      return
    }
    guard let lastUpdated = Self.date(from: value) else {
      throw DecodingError.dataCorruptedError(
        forKey: .lastUpdated,
        in: container,
        debugDescription: "Expected an ISO 8601 Home Assistant timestamp."
      )
    }
    self.lastUpdated = lastUpdated
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

  private static func date(from value: String) -> Date? {
    if let date = try? Date(
      value,
      strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    ) {
      return date
    }
    return try? Date(
      value,
      strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    )
  }
}

private struct HomeAssistantStateAttributes: Decodable, Equatable, Sendable {
  let currentTemperature: Double?
  let targetTemperature: Double?
  let deviceClass: String?
  let friendlyName: String?
  let icon: String?
  let hvacModes: [String]?
  let minimumTemperature: Double?
  let maximumTemperature: Double?
  let targetTemperatureStep: Double?
  let temperaturePrecision: Double?
  let options: [String]?
  let unitOfMeasurement: String?
  let currentPosition: Double?
  let supportedFeatures: Int?

  enum CodingKeys: String, CodingKey {
    case currentTemperature = "current_temperature"
    case targetTemperature = "temperature"
    case deviceClass = "device_class"
    case friendlyName = "friendly_name"
    case icon
    case hvacModes = "hvac_modes"
    case minimumTemperature = "min_temp"
    case maximumTemperature = "max_temp"
    case targetTemperatureStep = "target_temp_step"
    case temperaturePrecision = "precision"
    case options
    case unitOfMeasurement = "unit_of_measurement"
    case currentPosition = "current_position"
    case supportedFeatures = "supported_features"
  }
}

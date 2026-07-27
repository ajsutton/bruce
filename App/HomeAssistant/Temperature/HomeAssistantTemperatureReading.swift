import Foundation

struct HomeAssistantTemperatureReading: Equatable, Identifiable, Sendable {
  enum ClimateMode: String, CaseIterable, Equatable, Hashable, Sendable {
    case automatic = "auto"
    case cooling = "cool"
    case drying = "dry"
    case fanOnly = "fan_only"
    case heating = "heat"
  }

  enum Kind: Equatable, Sendable {
    case airConditioner
    case zone
    case other
  }

  enum OperatingMode: Equatable, Sendable {
    case automatic
    case cooling
    case drying
    case fanOnly
    case heating
    case off
    case active
    case unavailable
  }

  enum PowerState: Equatable, Sendable {
    case poweredOn
    case off
    case unavailable
  }

  let id: String
  let name: String
  let value: Double
  let targetValue: Double?
  let unit: String?
  let powerState: PowerState
  let kind: Kind
  let operatingMode: OperatingMode
  let availableModes: [ClimateMode]
  let icon: String?

  init(
    id: String,
    name: String,
    value: Double,
    targetValue: Double?,
    unit: String?,
    powerState: PowerState,
    kind: Kind = .other,
    operatingMode: OperatingMode = .active,
    availableModes: [ClimateMode] = [],
    icon: String? = nil
  ) {
    self.id = id
    self.name = name
    self.value = value
    self.targetValue = targetValue
    self.unit = unit
    self.powerState = powerState
    self.kind = kind
    self.operatingMode = operatingMode
    self.availableModes = availableModes
    self.icon = icon
  }

}

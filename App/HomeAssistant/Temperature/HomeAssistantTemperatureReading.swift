import Foundation

struct HomeAssistantTemperatureReading: Equatable, Identifiable, Sendable {
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
  let icon: String?

  init(
    id: String,
    name: String,
    value: Double,
    targetValue: Double?,
    unit: String?,
    powerState: PowerState,
    icon: String? = nil
  ) {
    self.id = id
    self.name = name
    self.value = value
    self.targetValue = targetValue
    self.unit = unit
    self.powerState = powerState
    self.icon = icon
  }
}

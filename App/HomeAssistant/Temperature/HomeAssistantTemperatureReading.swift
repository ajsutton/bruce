import Foundation

struct HomeAssistantTemperatureReading: Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let value: Double
  let unit: String?
  let icon: String?

  init(
    id: String,
    name: String,
    value: Double,
    unit: String?,
    icon: String? = nil
  ) {
    self.id = id
    self.name = name
    self.value = value
    self.unit = unit
    self.icon = icon
  }
}

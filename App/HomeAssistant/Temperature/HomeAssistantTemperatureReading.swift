import Foundation

struct HomeAssistantTemperatureReading: Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let value: Double
  let unit: String?
  let updatedAt: Date?
  let icon: String?

  init(
    id: String,
    name: String,
    value: Double,
    unit: String?,
    updatedAt: Date?,
    icon: String? = nil
  ) {
    self.id = id
    self.name = name
    self.value = value
    self.unit = unit
    self.updatedAt = updatedAt
    self.icon = icon
  }
}

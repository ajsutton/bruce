import Foundation

struct HomeAssistantTemperatureReading: Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let value: Double
  let unit: String?
  let updatedAt: Date?
}

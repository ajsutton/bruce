import Foundation

struct HomeAssistantClimateFloor: Equatable, Sendable {
  let id: String
  let name: String
  let level: Int?
}

struct HomeAssistantClimatePresetLabel: Equatable, Hashable, Sendable {
  let id: String
  let name: String
}

struct HomeAssistantClimatePreset: Equatable, Identifiable, Sendable {
  enum Identifier: Equatable, Hashable, Sendable {
    case all
    case label(String)
    case floor(String)
    case none
  }

  let id: Identifier
  let name: String
  let zoneEntityIDs: Set<String>

  func matches(_ zones: [HomeAssistantTemperatureReading]) -> Bool {
    guard zones.allSatisfy({ $0.powerState != .unavailable }) else { return false }
    return zones.allSatisfy { zone in
      let shouldBeOn = zoneEntityIDs.contains(zone.id)
      return shouldBeOn == (zone.powerState == .poweredOn)
    }
  }
}

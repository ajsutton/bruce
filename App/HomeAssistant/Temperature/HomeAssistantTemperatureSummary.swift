import Foundation

struct HomeAssistantTemperatureSummary {
  let airConditioners: [HomeAssistantTemperatureReading]
  let rooms: [HomeAssistantTemperatureReading]

  init(readings: [HomeAssistantTemperatureReading]) {
    airConditioners = readings.filter { $0.kind == .airConditioner }
    rooms = readings.filter { $0.kind != .airConditioner }
  }

  var averageRoomTemperature: Double? {
    let availableValues = rooms.compactMap { reading in
      reading.powerState == .unavailable ? nil : reading.value
    }
    guard !availableValues.isEmpty else {
      return nil
    }
    return availableValues.reduce(0, +) / Double(availableValues.count)
  }

  var targetValueFractionLength: Int {
    (airConditioners + rooms)
      .filter { $0.targetValue != nil }
      .map(\.targetValueFractionLength)
      .max() ?? 1
  }

  var climatePresets: [HomeAssistantClimatePreset] {
    let zones = rooms.filter { $0.kind == .zone }
    guard !zones.isEmpty else { return [] }

    let all = HomeAssistantClimatePreset(
      id: .all,
      name: "",
      zoneEntityIDs: Set(zones.map(\.id))
    )
    let labelPresets = Dictionary(
      grouping: zones.flatMap { zone in
        zone.presetLabels.map { ($0, zone.id) }
      }, by: { $0.0.id }
    )
    .compactMap { _, members -> HomeAssistantClimatePreset? in
      guard let label = members.first?.0 else { return nil }
      return HomeAssistantClimatePreset(
        id: .label(label.id),
        name: label.name,
        zoneEntityIDs: Set(members.map(\.1))
      )
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    let floorPresets = Dictionary(
      grouping: zones.compactMap { zone in
        zone.floor.map { ($0, zone.id) }
      }, by: { $0.0.id }
    )
    .compactMap { _, members -> (HomeAssistantClimateFloor, HomeAssistantClimatePreset)? in
      guard let floor = members.first?.0 else { return nil }
      return (
        floor,
        HomeAssistantClimatePreset(
          id: .floor(floor.id),
          name: floor.name,
          zoneEntityIDs: Set(members.map(\.1))
        )
      )
    }
    .sorted { lhs, rhs in
      switch (lhs.0.level, rhs.0.level) {
      case (.some(let lhsLevel), .some(let rhsLevel)) where lhsLevel != rhsLevel:
        lhsLevel < rhsLevel
      case (.some, .none):
        true
      case (.none, .some):
        false
      default:
        lhs.1.name.localizedStandardCompare(rhs.1.name) == .orderedAscending
      }
    }
    .map(\.1)
    let none = HomeAssistantClimatePreset(
      id: .none,
      name: "",
      zoneEntityIDs: []
    )
    return [all] + labelPresets + floorPresets + [none]
  }

  var selectedClimatePresetID: HomeAssistantClimatePreset.Identifier? {
    let zones = rooms.filter { $0.kind == .zone }
    return climatePresets.first(where: { $0.matches(zones) })?.id
  }
}

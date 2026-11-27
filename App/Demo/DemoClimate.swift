import Foundation

final class DemoClimate: HomeAssistantTemperatureLoading, HomeAssistantClimateControlling {
  private let state = DemoValue([
    HomeAssistantTemperatureReading(
      id: ClimateHistoryZone.systemID, name: "House", value: 23.4, targetValue: nil, unit: "°C",
      powerState: .poweredOn, kind: .airConditioner, operatingMode: .cooling,
      availableModes: HomeAssistantTemperatureReading.ClimateMode.allCases
    ),
    HomeAssistantTemperatureReading(
      id: "climate.lounge", name: "Lounge", value: 23.4, targetValue: 22,
      unit: "°C", powerState: .poweredOn, kind: .zone, operatingMode: .cooling,
      minimumTargetValue: 16, maximumTargetValue: 30,
      presetLabels: [HomeAssistantClimatePresetLabel(id: "day", name: "Day")]
    ),
    HomeAssistantTemperatureReading(
      id: "climate.master_bed", name: "Master Bed", value: 22.1, targetValue: 21,
      unit: "°C", powerState: .off, kind: .zone, operatingMode: .off,
      minimumTargetValue: 16, maximumTargetValue: 30,
      presetLabels: [HomeAssistantClimatePresetLabel(id: "night", name: "Night")]
    ),
  ])

  var providesContinuousTemperatureUpdates: Bool { true }

  func temperatureUpdates() -> HomeAssistantTemperatureUpdateStream {
    HomeAssistantTemperatureUpdateStream { [state] continuation in
      let id = state.observe { continuation.yield(.live($0)) }
      continuation.onTermination = { [weak state] _ in state?.removeObserver(id) }
    }
  }

  func setPower(entityID: String, isOn: Bool) async throws {
    try change(entityID) {
      $0.replacingClimateState(
        powerState: isOn ? .poweredOn : .off,
        operatingMode: isOn ? .cooling : .off
      )
    }
  }

  func setTargetValue(_ value: Double, entityID: String) async throws {
    try change(entityID) { $0.replacingTargetValue(value) }
  }

  func setOpening(_ value: Double, entityID: String) async throws {
    throw DemoHomeError.unsupportedControl
  }

  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode, entityID: String
  ) async throws {
    let operatingMode: HomeAssistantTemperatureReading.OperatingMode
    switch mode {
    case .automatic: operatingMode = .automatic
    case .cooling: operatingMode = .cooling
    case .drying: operatingMode = .drying
    case .fanOnly: operatingMode = .fanOnly
    case .heating: operatingMode = .heating
    }
    try change(entityID) {
      $0.replacingClimateState(powerState: .poweredOn, operatingMode: operatingMode)
    }
  }

  private func change(
    _ entityID: String,
    transform: (HomeAssistantTemperatureReading) -> HomeAssistantTemperatureReading
  ) throws {
    try Task.checkCancellation()
    try state.update { readings in
      guard let index = readings.firstIndex(where: { $0.id == entityID }) else {
        throw DemoHomeError.unknownEntity
      }
      readings[index] = transform(readings[index])
    }
  }
}

enum DemoHomeError: Error, Equatable {
  case unknownEntity
  case unsupportedControl
}

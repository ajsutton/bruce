import SwiftUI

#Preview("Bruce") {
  HomeAssistantTemperaturePreview.view(mode: .standard)
}

#Preview("Full Bruce") {
  HomeAssistantTemperaturePreview.view(mode: .full)
}

#Preview("Bruce Empty") {
  HomeAssistantTemperaturePreview.view(mode: .standard, readings: [])
}

#Preview("Full Bruce Connection Problem") {
  HomeAssistantConnectionBannerView(
    banner: HomeAssistantConnectionBanner(problem: .signInRequired),
    lastSuccessfulUpdate: .now,
    mode: .full,
    manageConnection: {},
    requestRefresh: {}
  )
  .background(BruceMode.full.backgroundColor)
}

#Preview("Bruce AC") {
  HomeAssistantAirConditionerCard(
    reading: HomeAssistantTemperaturePreview.airConditioner,
    averageValue: 22.8,
    mode: .standard,
    showsControls: true,
    isControlEnabled: true
  )
  .padding()
}

#Preview("Full Bruce AC") {
  HomeAssistantAirConditionerCard(
    reading: HomeAssistantTemperaturePreview.airConditioner,
    averageValue: 22.8,
    mode: .full,
    showsControls: true,
    isControlEnabled: true
  )
  .padding()
  .background(BruceMode.full.backgroundColor)
}

#Preview("Climate Presets") {
  let summary = HomeAssistantTemperatureSummary(
    readings: HomeAssistantTemperaturePreview.previewTemperatureReadings
  )
  HomeAssistantAirConditionerCard(
    reading: HomeAssistantTemperaturePreview.airConditioner,
    averageValue: summary.averageRoomTemperature,
    mode: .standard,
    showsControls: true,
    isControlEnabled: true,
    climatePresets: summary.climatePresets,
    selectedClimatePresetID: summary.selectedClimatePresetID,
    canApplyClimatePreset: true
  )
  .frame(width: 900)
  .padding()
}

#Preview("Narrow Climate Presets") {
  let summary = HomeAssistantTemperatureSummary(
    readings: HomeAssistantTemperaturePreview.previewTemperatureReadings
  )
  HomeAssistantAirConditionerCard(
    reading: HomeAssistantTemperaturePreview.airConditioner,
    averageValue: summary.averageRoomTemperature,
    mode: .standard,
    showsControls: true,
    isControlEnabled: true,
    climatePresets: summary.climatePresets,
    selectedClimatePresetID: summary.selectedClimatePresetID,
    canApplyClimatePreset: true
  )
  .frame(width: 360)
  .padding()
}

#Preview("Bruce Zone Controls") {
  VStack(spacing: 14) {
    HomeAssistantAirConditionerCard(
      reading: HomeAssistantTemperaturePreview.airConditioner,
      averageValue: 22.8,
      mode: .standard,
      showsControls: true,
      isControlEnabled: true,
      targetValueFractionLength: 1
    )

    HomeAssistantTemperatureCard(
      reading: HomeAssistantTemperaturePreview.livingRoom,
      mode: .standard,
      showsControl: true,
      isControlEnabled: true,
      showsTargetControl: true,
      targetValueFractionLength: 1
    )
  }
  .padding()
}

#Preview("Narrow Zone Controls") {
  HomeAssistantTemperatureCard(
    reading: HomeAssistantTemperaturePreview.livingRoom.replacingTargetValue(18.5),
    mode: .standard,
    showsControl: true,
    isControlEnabled: true,
    isTargetControlling: true,
    showsTargetControl: true,
    targetValueFractionLength: 1
  )
  .frame(width: 300)
  .padding()
}

private enum HomeAssistantTemperaturePreview {
  @MainActor
  static func view(
    mode: BruceMode,
    readings: [HomeAssistantTemperatureReading] = previewTemperatureReadings
  ) -> some View {
    let store = HomeAssistantTemperatureStore(
      loader: PreviewHomeAssistantTemperatureLoader(readings: readings),
      controller: PreviewHomeAssistantClimateController()
    )
    return HomeAssistantTemperatureView(
      store: store,
      mode: mode,
      isConnecting: false,
      showsConnectionProblems: true,
      requestRefresh: {}
    )
    .task {
      await store.load()
    }
  }

  static let airConditioner = HomeAssistantTemperatureReading(
    id: "climate.ac_0",
    name: "AC 0",
    value: 24,
    targetValue: 18,
    unit: "°C",
    powerState: .poweredOn,
    kind: .airConditioner,
    operatingMode: .cooling,
    availableModes: [.heating, .cooling, .automatic, .drying, .fanOnly]
  )

  static let livingRoom = HomeAssistantTemperatureReading(
    id: "climate.living_room",
    name: "Living Room",
    value: 26,
    targetValue: 18,
    unit: "°C",
    powerState: .poweredOn,
    kind: .zone,
    operatingMode: .fanOnly,
    icon: "mdi:sofa",
    minimumTargetValue: 16,
    maximumTargetValue: 30,
    targetValueStep: 0.5,
    floor: HomeAssistantClimateFloor(id: "downstairs", name: "Downstairs", level: 0)
  )

  static let bedroomsPreset = HomeAssistantClimatePresetLabel(
    id: "climate_preset_bedrooms",
    name: "Bedrooms"
  )

  static let previewTemperatureReadings = [
    airConditioner,
    livingRoom.replacingClimateState(powerState: .off, operatingMode: .off),
    HomeAssistantTemperatureReading(
      id: "climate.bedroom",
      name: "Master Bedroom",
      value: 21.8,
      targetValue: 22,
      unit: "°C",
      powerState: .poweredOn,
      kind: .zone,
      operatingMode: .fanOnly,
      icon: "mdi:bed",
      minimumTargetValue: 16,
      maximumTargetValue: 30,
      targetValueStep: 0.5,
      floor: HomeAssistantClimateFloor(id: "upstairs", name: "Upstairs", level: 1),
      presetLabels: [bedroomsPreset]
    ),
    HomeAssistantTemperatureReading(
      id: "climate.ella",
      name: "Ella's Bedroom",
      value: 22.2,
      targetValue: 22,
      unit: "°C",
      powerState: .poweredOn,
      kind: .zone,
      operatingMode: .fanOnly,
      icon: "mdi:bed",
      minimumTargetValue: 16,
      maximumTargetValue: 30,
      targetValueStep: 0.5,
      floor: HomeAssistantClimateFloor(id: "upstairs", name: "Upstairs", level: 1),
      presetLabels: [bedroomsPreset]
    ),
    HomeAssistantTemperatureReading(
      id: "climate.study",
      name: "Study",
      value: 22.6,
      targetValue: nil,
      unit: "°C",
      powerState: .off,
      kind: .zone,
      operatingMode: .off,
      icon: "mdi:desk",
      floor: HomeAssistantClimateFloor(id: "upstairs", name: "Upstairs", level: 1)
    ),
    HomeAssistantTemperatureReading(
      id: "climate.dining_room",
      name: "Dining Room",
      value: 24.1,
      targetValue: 24.5,
      unit: "°C",
      powerState: .off,
      kind: .zone,
      operatingMode: .off,
      icon: "mdi:table-chair",
      floor: HomeAssistantClimateFloor(id: "downstairs", name: "Downstairs", level: 0)
    ),
  ]
}

private struct PreviewHomeAssistantClimateController: HomeAssistantClimateControlling {
  func setPower(entityID: String, isOn: Bool) {}

  func setTargetValue(_ value: Double, entityID: String) {}

  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) {}
}

private struct PreviewHomeAssistantTemperatureLoader: HomeAssistantTemperatureLoading {
  let readings: [HomeAssistantTemperatureReading]
  let providesContinuousTemperatureUpdates = true

  func temperatureUpdates() -> HomeAssistantTemperatureUpdateStream {
    HomeAssistantTemperatureUpdateStream { continuation in
      continuation.yield(.live(readings))
    }
  }
}

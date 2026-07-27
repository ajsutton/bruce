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

#Preview("Full Bruce Problem") {
  HomeAssistantTemperaturePreview.view(
    mode: .full,
    connectionProblem: "Sign in to Home Assistant again to update temperatures."
  )
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
    connectionProblem: String? = nil,
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
      connectionProblem: connectionProblem,
      manageConnection: {},
      requestRefresh: {},
      isRemovingConnection: false
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
    targetValueStep: 0.5
  )

  private static let previewTemperatureReadings = [
    airConditioner,
    livingRoom,
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
      targetValueStep: 0.5
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
      icon: "mdi:desk"
    ),
    HomeAssistantTemperatureReading(
      id: "climate.dining_room",
      name: "Dining Room",
      value: 24.1,
      targetValue: 24.5,
      unit: "°C",
      powerState: .unavailable,
      kind: .zone,
      operatingMode: .unavailable,
      icon: "mdi:table-chair"
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

  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      continuation.yield(.live(readings))
      continuation.finish()
    }
  }
}

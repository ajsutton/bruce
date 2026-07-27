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

private enum HomeAssistantTemperaturePreview {
  @MainActor
  static func view(
    mode: BruceMode,
    connectionProblem: String? = nil,
    readings: [HomeAssistantTemperatureReading] = previewTemperatureReadings
  ) -> some View {
    let store = HomeAssistantTemperatureStore(
      loader: PreviewHomeAssistantTemperatureLoader(readings: readings)
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

  private static let previewTemperatureReadings = [
    HomeAssistantTemperatureReading(
      id: "climate.living_room",
      name: "Living Room",
      value: 23.4,
      unit: "°C",
      updatedAt: .now,
      icon: "mdi:sofa"
    ),
    HomeAssistantTemperatureReading(
      id: "climate.bedroom",
      name: "Master Bedroom",
      value: 21.8,
      unit: "°C",
      updatedAt: .now,
      icon: "mdi:bed"
    ),
    HomeAssistantTemperatureReading(
      id: "climate.study",
      name: "Study",
      value: 22.6,
      unit: "°C",
      updatedAt: .now.addingTimeInterval(-180),
      icon: "mdi:desk"
    ),
    HomeAssistantTemperatureReading(
      id: "climate.dining_room",
      name: "Dining Room",
      value: 24.1,
      unit: "°C",
      updatedAt: nil,
      icon: "mdi:table-chair"
    ),
  ]
}

private struct PreviewHomeAssistantTemperatureLoader: HomeAssistantTemperatureLoading {
  let readings: [HomeAssistantTemperatureReading]

  func loadTemperatures() async throws -> [HomeAssistantTemperatureReading] {
    readings
  }
}

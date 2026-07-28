import SwiftUI

struct BrucePanelsView: View {
  @ObservedObject var temperatureStore: HomeAssistantTemperatureStore
  let mode: BruceMode
  let isConnecting: Bool
  let connectionProblem: String?
  let manageConnection: () -> Void
  let requestTemperatureRefresh: () -> Void
  let isRemovingConnection: Bool

  var body: some View {
    TabView {
      Tab("Climate", systemImage: "thermometer") {
        HomeAssistantTemperatureView(
          store: temperatureStore,
          mode: mode,
          isConnecting: isConnecting,
          connectionProblem: connectionProblem,
          manageConnection: manageConnection,
          requestRefresh: requestTemperatureRefresh,
          isRemovingConnection: isRemovingConnection
        )
      }
    }
    .tabViewStyle(.sidebarAdaptable)
  }
}

#Preview("Panels") {
  BrucePanelsPreview.view
}

private enum BrucePanelsPreview {
  @MainActor
  static var view: some View {
    let store = HomeAssistantTemperatureStore(loader: BrucePanelsPreviewLoader())
    return BrucePanelsView(
      temperatureStore: store,
      mode: .standard,
      isConnecting: false,
      connectionProblem: nil,
      manageConnection: {},
      requestTemperatureRefresh: {},
      isRemovingConnection: false
    )
    .tint(BruceMode.standard.accentColor)
    .task {
      await store.load()
    }
  }
}

private struct BrucePanelsPreviewLoader: HomeAssistantTemperatureLoading {
  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      continuation.yield(
        .live([
          HomeAssistantTemperatureReading(
            id: "climate.living_room",
            name: "Living Room",
            value: 23.4,
            targetValue: 22,
            unit: "°C",
            powerState: .poweredOn,
            kind: .zone,
            operatingMode: .cooling,
            icon: "mdi:sofa"
          )
        ])
      )
      continuation.finish()
    }
  }
}

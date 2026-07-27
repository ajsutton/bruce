import SwiftUI

struct HomeAssistantTemperatureView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var store: HomeAssistantTemperatureStore
  let isConnecting: Bool
  let connectionProblem: String?
  let manageConnection: () -> Void
  let requestRefresh: () -> Void

  private var displayedProblem: String? {
    connectionProblem ?? store.problem?.message
  }

  private var isAwaitingFirstLoad: Bool {
    !isConnecting && connectionProblem == nil && store.lastChecked == nil && store.problem == nil
  }

  private var problemNeedsConnectionManagement: Bool {
    connectionProblem != nil || store.problem == .signInRequired
  }

  private var columns: [GridItem] {
    if dynamicTypeSize.isAccessibilitySize {
      return [GridItem(.flexible())]
    }
    return [GridItem(.adaptive(minimum: 160), spacing: 16)]
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if let displayedProblem {
          problemBanner(displayedProblem)
        }
        temperatureContent
      }
      .navigationTitle("Temperatures")
      .toolbar {
        ToolbarItem {
          Button("Manage Connection", systemImage: "gearshape") {
            manageConnection()
          }
        }
      }
    }
  }

  @ViewBuilder
  private var temperatureContent: some View {
    if store.readings.isEmpty {
      emptyState
    } else {
      ScrollView {
        LazyVGrid(
          columns: columns,
          spacing: 16
        ) {
          ForEach(store.readings) { reading in
            temperatureCard(reading)
          }
        }
        .padding()
      }
      .safeAreaInset(edge: .bottom) {
        updateStatus
          .padding(.horizontal)
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity)
          .background(.bar)
      }
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      if isConnecting || store.isLoading || isAwaitingFirstLoad {
        Label("Loading Temperatures", systemImage: "thermometer.medium")
      } else if displayedProblem != nil {
        Label("Temperatures Unavailable", systemImage: "thermometer.medium.slash")
      } else {
        Label("No Temperature Sensors", systemImage: "thermometer.medium")
      }
    } description: {
      if isConnecting {
        Text("Connecting to Home Assistant.")
      } else if store.isLoading || isAwaitingFirstLoad {
        Text("Checking the available sensors.")
      } else if displayedProblem == nil {
        Text("Bruce couldn’t find any available temperature sensors.")
      }
    } actions: {
      if isConnecting || store.isLoading || isAwaitingFirstLoad {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel(isConnecting ? "Connecting" : "Loading temperatures")
      }
    }
    .padding()
  }

  private func temperatureCard(_ reading: HomeAssistantTemperatureReading) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(reading.name)
        .font(.headline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(reading.value, format: .number.precision(.fractionLength(0...1)))
        if let unit = reading.unit {
          Text(unit)
        }
      }
      .font(.system(.title, design: .rounded, weight: .semibold))

      if let updatedAt = reading.updatedAt {
        HStack(spacing: 4) {
          Text("Updated")
          Text(updatedAt, style: .relative)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        Text("Update time unavailable")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
  }

  private func problemBanner(_ message: String) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
        .accessibilityHidden(true)

      Text(message)
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)

      if problemNeedsConnectionManagement {
        Button("Manage", action: manageConnection)
          .frame(minWidth: 44, minHeight: 44)
      } else {
        Button("Try Again", action: requestRefresh)
          .frame(minWidth: 44, minHeight: 44)
      }
    }
    .padding()
    .background(.red.opacity(0.1))
    .accessibilityElement(children: .contain)
  }

  private var updateStatus: some View {
    HStack(spacing: 8) {
      if isConnecting || store.isLoading {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel(isConnecting ? "Connecting" : "Updating temperatures")
      }
      if let lastChecked = store.lastChecked {
        Text("Checked")
        Text(lastChecked, style: .relative)
      } else if isConnecting {
        Text("Connecting")
      } else if store.isLoading {
        Text("Updating")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .accessibilityElement(children: .combine)
  }
}

#Preview("Temperatures") {
  let store = HomeAssistantTemperatureStore(
    loader: PreviewHomeAssistantTemperatureLoader()
  )
  HomeAssistantTemperatureView(
    store: store,
    isConnecting: false,
    connectionProblem: nil,
    manageConnection: {},
    requestRefresh: {}
  )
  .task {
    await store.load()
  }
}

private struct PreviewHomeAssistantTemperatureLoader: HomeAssistantTemperatureLoading {
  func loadTemperatures() async throws -> [HomeAssistantTemperatureReading] {
    [
      HomeAssistantTemperatureReading(
        id: "sensor.living_room_temperature",
        name: "Living Room",
        value: 23.4,
        unit: "°C",
        updatedAt: .now
      ),
      HomeAssistantTemperatureReading(
        id: "sensor.bedroom_temperature",
        name: "Bedroom",
        value: 21.8,
        unit: "°C",
        updatedAt: .now
      ),
    ]
  }
}

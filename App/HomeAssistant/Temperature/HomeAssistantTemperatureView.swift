import SwiftUI

struct HomeAssistantTemperatureView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var store: HomeAssistantTemperatureStore
  let isConnecting: Bool
  let connectionProblem: String?
  let manageConnection: () -> Void
  let requestRefresh: () -> Void
  let isRemovingConnection: Bool

  private var displayedProblem: String? {
    connectionProblem ?? store.problem?.message
  }

  private var isAwaitingFirstLoad: Bool {
    !isConnecting && connectionProblem == nil && store.lastChecked == nil && store.problem == nil
  }

  private var problemNeedsConnectionManagement: Bool {
    connectionProblem != nil || store.problem == .signInRequired
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if let displayedProblem {
          problemBanner(displayedProblem)
        }
        temperatureContent
      }
      .navigationTitle("Current Temperatures")
    }
  }

  @ViewBuilder
  private var temperatureContent: some View {
    if store.readings.isEmpty && !showsActivity {
      emptyState
    } else {
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(store.readings) { reading in
            temperatureCard(reading)
          }
        }
        .padding()
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
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

  private var showsActivity: Bool {
    isRemovingConnection || isConnecting || store.isLoading || isAwaitingFirstLoad
  }

  private var emptyState: some View {
    ContentUnavailableView {
      if displayedProblem != nil {
        Label("Temperatures Unavailable", systemImage: "thermometer.medium.slash")
      } else {
        Label("No Current Temperatures", systemImage: "thermometer.medium")
      }
    } description: {
      if displayedProblem == nil {
        Text("Bruce couldn’t find a current temperature from any air conditioner.")
      }
    }
    .padding()
  }

  private func temperatureCard(_ reading: HomeAssistantTemperatureReading) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 16) {
          temperatureLocation(reading)
          Divider()
          currentTemperature(reading)
        }
      } else {
        HStack(spacing: 20) {
          temperatureLocation(reading)
            .frame(maxWidth: .infinity, alignment: .leading)
          Divider()
          currentTemperature(reading)
            .frame(minWidth: 132, alignment: .leading)
        }
        .frame(minHeight: 88)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(.background, in: RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(.separator.opacity(0.35), lineWidth: 0.5)
    }
    .accessibilityElement(children: .combine)
  }

  private func temperatureLocation(
    _ reading: HomeAssistantTemperatureReading
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(reading.name)
        .font(.headline)

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
  }

  private func currentTemperature(
    _ reading: HomeAssistantTemperatureReading
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Current")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(reading.value, format: .number.precision(.fractionLength(0...1)))
        if let unit = reading.unit {
          Text(unit)
            .font(.title2)
        }
      }
      .font(.system(.largeTitle, design: .rounded, weight: .medium))
      .monospacedDigit()
    }
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
      if showsActivity {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel(progressAccessibilityLabel)
      }
      if isRemovingConnection {
        Text("Removing connection")
      } else if let lastChecked = store.lastChecked {
        Text("Checked")
        Text(lastChecked, style: .relative)
      } else if isConnecting {
        Text("Checking connection")
      } else if store.isLoading {
        Text("Updating")
      }
      Spacer()
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .accessibilityElement(children: .combine)
  }

  private var progressAccessibilityLabel: String {
    if isRemovingConnection {
      return "Removing connection"
    }
    return isConnecting ? "Checking connection" : "Updating temperatures"
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
    requestRefresh: {},
    isRemovingConnection: false
  )
  .task {
    await store.load()
  }
}

private struct PreviewHomeAssistantTemperatureLoader: HomeAssistantTemperatureLoading {
  func loadTemperatures() async throws -> [HomeAssistantTemperatureReading] {
    [
      HomeAssistantTemperatureReading(
        id: "climate.living_room",
        name: "Living Room",
        value: 23.4,
        unit: "°C",
        updatedAt: .now
      ),
      HomeAssistantTemperatureReading(
        id: "climate.bedroom",
        name: "Master Bedroom",
        value: 21.8,
        unit: "°C",
        updatedAt: .now
      ),
      HomeAssistantTemperatureReading(
        id: "climate.study",
        name: "Study",
        value: 22.6,
        unit: "°C",
        updatedAt: .now.addingTimeInterval(-180)
      ),
      HomeAssistantTemperatureReading(
        id: "climate.dining_room",
        name: "Dining Room",
        value: 24.1,
        unit: "°C",
        updatedAt: nil
      ),
    ]
  }
}

import SwiftUI

struct HomeAssistantTemperatureView: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject var store: HomeAssistantTemperatureStore
  let mode: BruceMode
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

  private var screenBackground: Color {
    if mode.isFullBruce {
      return mode.backgroundColor
    }
    if colorScheme == .dark {
      return Color(red: 0.13, green: 0.14, blue: 0.13)
    }
    return mode.backgroundColor
  }

  private var primaryCardForeground: AnyShapeStyle {
    mode.isFullBruce ? AnyShapeStyle(mode.foregroundColor) : AnyShapeStyle(.primary)
  }

  private var secondaryCardForeground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color.white.opacity(0.78))
      : AnyShapeStyle(.secondary)
  }

  private var problemForeground: AnyShapeStyle {
    mode.isFullBruce ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if let displayedProblem {
          problemBanner(displayedProblem)
        }
        temperatureContent
      }
      .background(screenBackground)
      .navigationTitle("Temperatures")
      .toolbarTitleDisplayMode(.inline)
      .tint(mode.accentColor)
      .modifier(TemperatureNavigationStyle(mode: mode))
    }
  }

  @ViewBuilder
  private var temperatureContent: some View {
    if store.readings.isEmpty && !showsActivity {
      emptyState
    } else {
      ScrollView {
        LazyVStack(spacing: 14) {
          ForEach(store.readings) { reading in
            HomeAssistantTemperatureCard(reading: reading, mode: mode)
          }

          updateStatus
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .padding()
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
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
    .foregroundStyle(primaryCardForeground)
  }

  private func problemBanner(_ message: String) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
        .accessibilityHidden(true)

      Text(message)
        .font(.callout)
        .foregroundStyle(problemForeground)
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
      } else if store.isLive {
        Text("Live")
      } else if let lastChecked = store.lastChecked {
        Text("Last checked")
        relativeDateText(lastChecked)
      } else if isConnecting {
        Text("Checking connection")
      } else if store.isLoading {
        Text("Updating")
      }
      Spacer()
    }
    .font(.caption)
    .foregroundStyle(secondaryCardForeground)
    .accessibilityElement(children: .combine)
  }

  private var progressAccessibilityLabel: String {
    if isRemovingConnection {
      return "Removing connection"
    }
    return isConnecting ? "Checking connection" : "Updating temperatures"
  }
}

private func relativeDateText(_ date: Date) -> Text {
  Text(
    .currentDate,
    format: Date.AnchoredRelativeFormatStyle(
      anchor: date,
      presentation: .named,
      unitsStyle: .wide
    )
  )
}

private struct TemperatureNavigationStyle: ViewModifier {
  let mode: BruceMode

  func body(content: Content) -> some View {
    #if os(iOS)
      content.toolbarColorScheme(mode.isFullBruce ? .dark : nil, for: .navigationBar)
    #else
      content
    #endif
  }
}

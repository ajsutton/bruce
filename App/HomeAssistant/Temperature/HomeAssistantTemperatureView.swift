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

  private var copy: TemperatureCopy {
    TemperatureCopy(mode: mode)
  }

  private var displayedProblem: String? {
    connectionProblem ?? store.problem.map(copy.problem)
  }

  private var isAwaitingFirstLoad: Bool {
    !isConnecting && connectionProblem == nil && store.lastChecked == nil && store.problem == nil
  }

  private var problemNeedsConnectionManagement: Bool {
    connectionProblem != nil || store.problem == .signInRequired
  }

  private var summary: HomeAssistantTemperatureSummary {
    HomeAssistantTemperatureSummary(readings: store.readings)
  }

  private var screenBackground: Color {
    mode.panelBackgroundColor(for: colorScheme)
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
      .navigationTitle(copy.navigationTitle)
      .toolbarTitleDisplayMode(.inline)
      .tint(mode.accentColor)
      .modifier(TemperatureNavigationStyle(mode: mode))
      .alert(
        copy.controlFailedTitle,
        isPresented: Binding(
          get: { store.controlProblem != nil },
          set: { isPresented in
            if !isPresented {
              store.dismissControlProblem()
            }
          }
        )
      ) {
        Button(copy.dismiss, role: .cancel) {}
      } message: {
        Text(store.controlProblem.map { copy.controlFailed(name: $0.name) } ?? "")
      }
    }
  }

  @ViewBuilder
  private var temperatureContent: some View {
    if store.readings.isEmpty && !showsActivity {
      emptyState
    } else {
      ScrollView {
        LazyVStack(spacing: 14) {
          ForEach(summary.airConditioners) { reading in
            HomeAssistantAirConditionerCard(
              reading: reading,
              averageValue: summary.averageRoomTemperature,
              mode: mode,
              showsName: summary.airConditioners.count > 1,
              showsControls: store.supportsControl,
              isControlEnabled: store.canControl(reading),
              isControlling: store.isControlling(entityID: reading.id),
              targetValueFractionLength: summary.targetValueFractionLength,
              setPower: { isOn in
                Task {
                  await store.setPower(for: reading, isOn: isOn)
                }
              },
              setMode: { climateMode in
                Task {
                  await store.setMode(climateMode, for: reading)
                }
              }
            )
            .padding(.bottom, 4)
          }

          ForEach(summary.rooms) { reading in
            HomeAssistantTemperatureCard(
              reading: reading,
              mode: mode,
              showsControl: reading.kind == .zone && store.supportsControl,
              isControlEnabled: store.canControl(reading),
              isControlling: store.isControllingClimateState(entityID: reading.id),
              isTargetControlling: store.isAdjustingTarget(entityID: reading.id),
              showsTargetControl: reading.kind == .zone
                && reading.targetValue != nil
                && store.supportsControl,
              targetValueFractionLength: summary.targetValueFractionLength,
              setPower: { isOn in
                Task {
                  await store.setPower(for: reading, isOn: isOn)
                }
              },
              setTargetValue: { value in
                MainActor.assumeIsolated {
                  store.setTargetValue(value, for: reading)
                }
              }
            )
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
        Label(copy.temperaturesUnavailable, systemImage: "thermometer.medium.slash")
      } else {
        Label(copy.noCurrentTemperatures, systemImage: "thermometer.medium")
      }
    } description: {
      if displayedProblem == nil {
        Text(copy.noCurrentTemperaturesDescription)
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
        Button(copy.manage, action: manageConnection)
          .frame(minWidth: 44, minHeight: 44)
      } else {
        Button(copy.tryAgain, action: requestRefresh)
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
        Text(copy.removingConnection)
      } else if store.isLive {
        Text(copy.live)
      } else if let lastChecked = store.lastChecked {
        Text(copy.lastChecked)
        relativeDateText(lastChecked)
      } else if isConnecting {
        Text(copy.checkingConnection)
      } else if store.isLoading {
        Text(copy.updating)
      }
      Spacer()
    }
    .font(.caption)
    .foregroundStyle(secondaryCardForeground)
    .accessibilityElement(children: .combine)
  }

  private var progressAccessibilityLabel: String {
    if isRemovingConnection {
      return copy.removingConnection
    }
    return isConnecting ? copy.checkingConnection : copy.updatingTemperatures
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

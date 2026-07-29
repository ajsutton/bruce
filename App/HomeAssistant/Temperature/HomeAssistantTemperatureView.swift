import SwiftUI

struct HomeAssistantTemperatureView: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject var store: HomeAssistantTemperatureStore
  let mode: BruceMode
  let isConnecting: Bool
  let showsConnectionProblems: Bool
  let requestRefresh: () -> Void

  private var copy: TemperatureCopy {
    TemperatureCopy(mode: mode)
  }

  private var displayedProblem: String? {
    guard
      let problem = store.problem,
      showsConnectionProblems || problem.isFeatureSpecific
    else {
      return nil
    }
    return copy.problem(problem)
  }

  private var isAwaitingFirstLoad: Bool {
    !isConnecting && store.lastChecked == nil && store.problem == nil
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
      VStack(spacing: 0) {
        if isDisplayingLastKnown {
          Text(copy.lastKnown)
            .font(.caption.weight(.medium))
            .foregroundStyle(problemForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
        }
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
                isLastKnown: isDisplayingLastKnown,
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
                isLastKnown: isDisplayingLastKnown,
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
          }
          .padding()
          .frame(maxWidth: 720)
          .frame(maxWidth: .infinity)
        }
      }
    }
  }

  private var showsActivity: Bool {
    isConnecting || store.isLoading || isAwaitingFirstLoad
  }

  private var isDisplayingLastKnown: Bool {
    !store.isLive && !store.readings.isEmpty
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

      Button(copy.tryAgain, action: requestRefresh)
        .frame(minWidth: 44, minHeight: 44)
    }
    .padding()
    .background(.red.opacity(0.1))
    .accessibilityElement(children: .contain)
  }
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

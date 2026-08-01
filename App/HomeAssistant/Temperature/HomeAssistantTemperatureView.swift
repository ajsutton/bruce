import SwiftUI

struct HomeAssistantTemperatureView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @ScaledMetric(relativeTo: .body) private var climateZoneMinimumWidth =
    BrucePanelLayout.climateZoneMinimumWidth
  @State private var panelWidth: CGFloat = 0
  @ObservedObject var store: HomeAssistantTemperatureStore
  let mode: BruceMode
  let isConnecting: Bool
  let showsConnectionProblems: Bool
  let requestRefresh: () -> Void
  var isEmbedded = false

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
    Group {
      if isEmbedded {
        panelContent
      } else {
        NavigationStack {
          panelContent
            .navigationTitle(copy.navigationTitle)
            .toolbarTitleDisplayMode(.inline)
            .modifier(TemperatureNavigationStyle(mode: mode))
        }
      }
    }
    .tint(mode.accentColor)
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

  private var panelContent: some View {
    VStack(spacing: 0) {
      if let displayedProblem {
        problemBanner(displayedProblem)
      }
      temperatureContent
    }
    .background(screenBackground)
    .onGeometryChange(for: CGFloat.self) { geometry in
      geometry.size.width
    } action: { width in
      panelWidth = width
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
        if isEmbedded {
          temperatureReadings
        } else {
          ScrollView {
            temperatureReadings
          }
        }
      }
    }
  }

  private var temperatureReadings: some View {
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
        .equatable()
        .padding(.bottom, 4)
      }

      if !summary.rooms.isEmpty {
        LazyVGrid(
          columns: climateZoneColumns,
          alignment: .leading,
          spacing: 14
        ) {
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
            .equatable()
          }
        }
      }
    }
    .padding(BrucePanelLayout.contentPadding)
    .frame(maxWidth: BrucePanelLayout.maximumContentWidth)
    .frame(maxWidth: .infinity)
  }

  private var climateZoneColumns: [GridItem] {
    if dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact
      || availableContentWidth < climateZoneMinimumWidth
    {
      return [GridItem(.flexible())]
    }
    return [
      GridItem(
        .adaptive(minimum: climateZoneMinimumWidth),
        spacing: 14,
        alignment: .top
      )
    ]
  }

  private var availableContentWidth: CGFloat {
    max(
      min(panelWidth, BrucePanelLayout.maximumContentWidth)
        - (BrucePanelLayout.contentPadding * 2),
      0
    )
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

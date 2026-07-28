import SwiftUI

struct HomeAssistantEVChargingCard: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var store: HomeAssistantEVChargingStore
  @FocusState private var isPickerFocused: Bool
  let mode: BruceMode
  let manageConnection: () -> Void
  let requestRefresh: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header

      chargingModePicker
        .disabled(!store.isLive)
        .allowsHitTesting(store.canSelectMode)
        .accessibilityRespondsToUserInteraction(store.canSelectMode)
        .focusable(store.canSelectMode)
        .focused($isPickerFocused)
        .accessibilityValue(accessibilityValue)
        .onChange(of: store.canSelectMode) { _, canSelectMode in
          if !canSelectMode {
            isPickerFocused = false
          }
        }

      HomeAssistantEVOperationalStatusView(
        activity: store.activity,
        isLive: store.isActivityLive,
        isLoading: store.isLoading,
        mode: mode
      )

      if let problem = store.problem {
        problemView(problem)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(borderColor, lineWidth: 1)
    }
    .shadow(
      color: .black.opacity(mode.isFullBruce ? 0.2 : 0.1),
      radius: 10,
      y: 4
    )
  }

  private func problemView(
    _ problem: HomeAssistantEVChargingStore.Problem
  ) -> some View {
    HStack(alignment: .center, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .accessibilityHidden(true)
        Text(problem.message)
          .foregroundStyle(primaryForeground)
      }
      .font(.footnote)
      .frame(maxWidth: .infinity, alignment: .leading)

      if problem.needsConnectionManagement {
        Button("Manage", action: manageConnection)
          .frame(minHeight: 44)
      } else {
        Button(problem.refreshButtonTitle, action: requestRefresh)
          .frame(minHeight: 44)
      }
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var chargingModePicker: some View {
    if dynamicTypeSize.isAccessibilitySize {
      Picker("Charging mode", selection: selection) {
        chargingModeOptions
      }
      .pickerStyle(.menu)
    } else {
      Picker("Charging mode", selection: selection) {
        chargingModeOptions
      }
      .pickerStyle(.segmented)
    }
  }

  @ViewBuilder
  private var chargingModeOptions: some View {
    ForEach(HomeAssistantEVChargingMode.allCases, id: \.self) { chargingMode in
      Text(chargingMode.title)
        .tag(Optional(chargingMode))
    }
  }

  @ViewBuilder
  private var header: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          chargerIcon
          Spacer()
          progress
        }
        chargerDescription
      }
    } else {
      HStack(spacing: 12) {
        chargerIcon
        chargerDescription
        Spacer()
        progress
      }
    }
  }

  private var chargerIcon: some View {
    Image(systemName: operationalIconPresentation.icon)
      .font(.title2)
      .foregroundStyle(iconForeground)
      .frame(width: 44, height: 44)
      .background(iconBackground, in: RoundedRectangle(cornerRadius: 12))
      .contentTransition(.symbolEffect(.replace))
      .accessibilityHidden(true)
  }

  private var chargerDescription: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Car charger")
        .font(.headline)
        .foregroundStyle(primaryForeground)
      Text(status)
        .font(.subheadline)
        .foregroundStyle(secondaryForeground)
    }
  }

  @ViewBuilder
  private var progress: some View {
    ZStack {
      if store.showsProgress {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel(progressLabel)
      }
    }
    .frame(width: 16, height: 16)
  }

  private var selection: Binding<HomeAssistantEVChargingMode?> {
    Binding(
      get: { store.mode },
      set: { selectedMode in
        guard let selectedMode else { return }
        Task {
          await store.selectMode(selectedMode)
        }
      }
    )
  }

  private var status: String {
    if store.isLoading && store.mode == nil {
      return "Checking mode"
    }
    if !store.isLive && !store.isLoading {
      return qualifiedStatus(prefix: "Last known")
    }
    return store.mode?.description(for: mode) ?? "Mode unavailable"
  }

  private func qualifiedStatus(prefix: String) -> String {
    guard let mode = store.mode else {
      return prefix == "Last known"
        ? "Mode unavailable"
        : prefix.replacingOccurrences(
          of: " — last known",
          with: ""
        )
    }
    return "\(prefix): \(mode.neutralDescription)"
  }

  private var progressLabel: String {
    store.isChanging ? "Changing charging mode" : "Checking charging mode"
  }

  private var accessibilityValue: String {
    if store.isChanging {
      return "\(store.mode?.title ?? "Requested mode"). Updating"
    }
    if store.isLoading, let currentMode = store.mode {
      return "\(currentMode.title). Checking current mode"
    }
    guard store.isLive else {
      return store.mode.map { "Last known: \($0.title)" } ?? "Unavailable"
    }
    return store.mode?.title ?? "Unavailable"
  }

  private var primaryForeground: AnyShapeStyle {
    mode.isFullBruce ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
  }

  private var secondaryForeground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color.white.opacity(0.76))
      : AnyShapeStyle(.secondary)
  }

  private var iconForeground: Color {
    if store.isActivityLive, store.activity.isCharging {
      return .white
    }
    if mode.isFullBruce {
      return mode.backgroundColor
    }
    return colorScheme == .dark ? mode.backgroundColor : mode.foregroundColor
  }

  private var iconBackground: Color {
    if store.isActivityLive, store.activity.isCharging {
      return operationalIconPresentation.color
    }
    if mode.isFullBruce {
      return mode.accentColor
    }
    return colorScheme == .dark
      ? mode.foregroundColor.opacity(0.72)
      : Color.white.opacity(0.82)
  }

  private var operationalIconPresentation: HomeAssistantEVActivityPresentation {
    HomeAssistantEVActivityPresentation(
      activity: store.isActivityLive ? store.activity : .unavailable,
      mode: mode
    )
  }

  private var cardBackground: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color(red: 0.00, green: 0.25, blue: 0.18))
      : AnyShapeStyle(.background)
  }

  private var borderColor: Color {
    if mode.isFullBruce {
      return mode.accentColor.opacity(0.28)
    }
    return colorScheme == .dark
      ? Color.white.opacity(0.08)
      : mode.foregroundColor.opacity(0.08)
  }
}

extension HomeAssistantEVChargingStore.Problem {
  fileprivate var refreshButtonTitle: String {
    self == .updateFailed || self == .updateTimedOut ? "Check Current Mode" : "Refresh"
  }
}

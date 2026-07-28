import SwiftUI

struct HomeAssistantEVChargingCard: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var store: HomeAssistantEVChargingStore
  @FocusState private var isPickerFocused: Bool
  let mode: BruceMode
  let manageConnection: () -> Void
  let requestRefresh: () -> Void

  private var copy: EVChargingCopy {
    EVChargingCopy(mode: mode)
  }

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
        Text(copy.problem(problem))
          .foregroundStyle(primaryForeground)
      }
      .font(.footnote)
      .frame(maxWidth: .infinity, alignment: .leading)

      if problem.needsConnectionManagement {
        Button(copy.manage, action: manageConnection)
          .frame(minHeight: 44)
      } else {
        Button(problem.refreshButtonTitle(copy: copy), action: requestRefresh)
          .frame(minHeight: 44)
      }
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var chargingModePicker: some View {
    if dynamicTypeSize.isAccessibilitySize {
      Picker(copy.chargingMode, selection: selection) {
        chargingModeOptions
      }
      .pickerStyle(.menu)
    } else {
      Picker(copy.chargingMode, selection: selection) {
        chargingModeOptions
      }
      .pickerStyle(.segmented)
    }
  }

  @ViewBuilder
  private var chargingModeOptions: some View {
    ForEach(HomeAssistantEVChargingMode.allCases, id: \.self) { chargingMode in
      Text(copy.chargingModeTitle(chargingMode))
        .tag(Optional(chargingMode))
        .accessibilityLabel(copy.chargingModeAccessibilityLabel(chargingMode))
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
      Text(copy.carCharger)
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
      return copy.checkingMode
    }
    if !store.isLive && !store.isLoading {
      return store.mode.map {
        copy.lastKnown(copy.chargingModeDescription($0))
      } ?? copy.modeUnavailable
    }
    return store.mode.map(copy.chargingModeDescription) ?? copy.modeUnavailable
  }

  private var progressLabel: String {
    store.isChanging ? copy.changingChargingMode : copy.checkingChargingMode
  }

  private var accessibilityValue: String {
    if store.isChanging {
      return "\(store.mode.map(copy.chargingModeTitle) ?? copy.requestedMode). \(copy.updating)"
    }
    if store.isLoading, let currentMode = store.mode {
      return "\(copy.chargingModeTitle(currentMode)). \(copy.checkingCurrentMode)"
    }
    guard store.isLive else {
      return store.mode.map { copy.lastKnown(copy.chargingModeTitle($0)) } ?? copy.unavailable
    }
    return store.mode.map(copy.chargingModeTitle) ?? copy.unavailable
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
  fileprivate func refreshButtonTitle(copy: EVChargingCopy) -> String {
    self == .updateFailed || self == .updateTimedOut ? copy.checkCurrentMode : copy.refresh
  }
}

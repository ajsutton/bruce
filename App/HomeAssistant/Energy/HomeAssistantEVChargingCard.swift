import SwiftUI

struct HomeAssistantEVChargingCard: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var store: HomeAssistantEVChargingStore
  @FocusState private var isPickerFocused: Bool
  let mode: BruceMode
  var showsConnectionProblems = true
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
        decisionPresentation: decisionPresentation,
        isActivityLive: store.isActivityLive,
        isDecisionLive: decisionIsLive,
        isLoading: store.isLoading,
        isRefreshing: store.isRefreshing,
        mode: mode
      )

      if let problem = store.problem,
        showsConnectionProblems || problem.isFeatureSpecific
      {
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

      if problem.offersRecoveryAction {
        if problem.needsConnectionManagement {
          Button(copy.manage, action: manageConnection)
            .frame(minHeight: 44)
        } else {
          Button(problem.refreshButtonTitle(copy: copy), action: requestRefresh)
            .frame(minHeight: 44)
        }
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
        if store.showsProgress {
          progress
        }
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
    if store.isRefreshing {
      return store.mode.map { copy.lastKnown(copy.chargingModeDescription($0)) } ?? copy.updating
    }
    if !store.isLive {
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
    if store.isRefreshing {
      return store.mode.map {
        copy.updating(lastKnown: copy.chargingModeTitle($0))
      } ?? copy.updating
    }
    if store.isLoading, let currentMode = store.mode {
      return "\(copy.chargingModeTitle(currentMode)). \(copy.checkingCurrentMode)"
    }
    guard store.isLive else {
      return store.mode.map { copy.lastKnown(copy.chargingModeTitle($0)) } ?? copy.unavailable
    }
    return store.mode.map(copy.chargingModeTitle) ?? copy.unavailable
  }
}

extension HomeAssistantEVChargingCard {
  private var chargerDescription: some View {
    VStack(alignment: .leading, spacing: 2) {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 6) {
          chargerTitle
          decisionMetrics
        }
      } else {
        HStack(spacing: 8) {
          chargerTitle
            .fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: 0)
          decisionMetrics
            .fixedSize()
        }
      }
      Text(status)
        .font(.subheadline)
        .foregroundStyle(secondaryForeground)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var chargerTitle: some View {
    Text(copy.carCharger)
      .font(.headline)
      .foregroundStyle(primaryForeground)
  }

  private var decisionMetrics: some View {
    HStack(spacing: 10) {
      Image(systemName: displayedIntent.icon)
        .foregroundStyle(intentColor)
        .accessibilityLabel(intentAccessibilityLabel)

      HStack(spacing: 3) {
        Image(systemName: "moon.stars")
          .accessibilityHidden(true)
        Text(displayedSafeChargingTime)
          .monospacedDigit()
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(copy.safeOvernightChargingTime)
      .accessibilityValue(
        metricAccessibilityValue(decisionPresentation.safeChargingTimeAccessibility)
      )

      HStack(spacing: 3) {
        Image(systemName: displayedBatteryIcon)
          .accessibilityHidden(true)
        Text(displayedBatteryStateOfCharge)
          .monospacedDigit()
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(copy.homeBattery)
      .accessibilityValue(
        metricAccessibilityValue(decisionPresentation.batteryStateOfCharge)
      )

      ZStack {
        Image(systemName: "clock")
          .opacity(!decisionIsLive && !decisionIsUpdating ? 1 : 0)
        Image(systemName: "arrow.clockwise")
          .opacity(!decisionIsLive && decisionIsUpdating ? 1 : 0)
      }
      .frame(width: 12)
      .accessibilityHidden(true)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(secondaryForeground)
  }

  private var decisionPresentation: EVChargingDecisionPresentation {
    EVChargingDecisionPresentation(
      decision: store.decision,
      chargingMode: store.mode ?? .off,
      mode: mode
    )
  }

  private var intentColor: Color {
    decisionIsLive && decisionPresentation.intent == .allowed ? .green : .secondary
  }

  private var displayedIntent: EVChargingDecisionPresentation.Intent { decisionPresentation.intent }

  private var displayedSafeChargingTime: String {
    store.decision.overnightSafeChargingMinutes == nil
      ? "—" : decisionPresentation.safeChargingTime
  }

  private var displayedBatteryStateOfCharge: String {
    store.decision.batteryStateOfCharge == nil
      ? "—" : decisionPresentation.batteryStateOfCharge
  }

  private var displayedBatteryIcon: String {
    decisionPresentation.batteryIcon
  }

  private var decisionIsLive: Bool {
    store.isDecisionLive && !store.isChanging && !store.isRefreshing
  }

  private var intentAccessibilityLabel: String {
    let value =
      switch decisionPresentation.intent {
      case .allowed: copy.chargingAllowed
      case .held: copy.chargingHeld
      case .unavailable: copy.chargingDecisionUnavailable
      }
    guard decisionPresentation.intent != .unavailable else { return value }
    guard !decisionIsLive else { return value }
    return decisionIsUpdating ? copy.updating(lastKnown: value) : copy.lastKnown(value)
  }

  private func metricAccessibilityValue(_ value: String) -> String {
    guard value != copy.unavailable else { return value }
    guard !decisionIsLive else { return value }
    return decisionIsUpdating ? copy.updating(lastKnown: value) : copy.lastKnown(value)
  }

  private var decisionIsUpdating: Bool {
    store.isLoading || store.isRefreshing || store.isChanging
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
    if presentsOperationalActivity, store.activity.isCharging {
      return .white
    }
    if mode.isFullBruce {
      return mode.backgroundColor
    }
    return colorScheme == .dark ? mode.backgroundColor : mode.foregroundColor
  }

  private var iconBackground: Color {
    if presentsOperationalActivity, store.activity.isCharging {
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
      activity: presentsOperationalActivity ? store.activity : .unavailable,
      mode: mode
    )
  }

  private var presentsOperationalActivity: Bool {
    store.isActivityLive || (store.isRefreshing && store.activity != .unavailable)
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

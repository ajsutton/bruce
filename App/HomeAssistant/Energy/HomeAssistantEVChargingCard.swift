import SwiftUI

struct HomeAssistantEVChargingCard: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var store: HomeAssistantEVChargingStore
  let mode: BruceMode
  let manageConnection: () -> Void
  let requestRefresh: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header

      chargingModePicker
        .disabled(!store.canSelectMode)
        .accessibilityValue(accessibilityValue)

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
    Image(systemName: "bolt.car")
      .font(.title2)
      .foregroundStyle(iconForeground)
      .frame(width: 44, height: 44)
      .background(iconBackground, in: RoundedRectangle(cornerRadius: 12))
      .accessibilityHidden(true)
  }

  private var chargerDescription: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("EV charger")
        .font(.headline)
        .foregroundStyle(primaryForeground)
      Text(status)
        .font(.subheadline)
        .foregroundStyle(secondaryForeground)
    }
  }

  @ViewBuilder
  private var progress: some View {
    if store.isLoading || store.isChanging {
      ProgressView()
        .accessibilityLabel(progressLabel)
    }
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
    if store.isChanging {
      return changingStatus
    }
    if store.isLoading {
      return qualifiedStatus(prefix: "Checking mode — last known")
    }
    if !store.isLive {
      return qualifiedStatus(prefix: "Last known")
    }
    return store.mode?.description(for: mode) ?? "Mode unavailable"
  }

  private var changingStatus: String {
    let target = store.pendingMode?.title ?? "mode"
    guard let confirmedMode = store.mode else {
      return "Changing to \(target)"
    }
    return "Changing to \(target) — last known: \(confirmedMode.neutralDescription)"
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
      let target = store.pendingMode?.title ?? "requested mode"
      let confirmed = store.mode?.title ?? "unavailable"
      return "Changing to \(target). Last known mode: \(confirmed)"
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
    if mode.isFullBruce {
      return mode.backgroundColor
    }
    return colorScheme == .dark ? mode.backgroundColor : mode.foregroundColor
  }

  private var iconBackground: Color {
    if mode.isFullBruce {
      return mode.accentColor
    }
    return colorScheme == .dark
      ? mode.foregroundColor.opacity(0.72)
      : Color.white.opacity(0.82)
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
    self == .updateFailed ? "Check Current Mode" : "Refresh"
  }
}

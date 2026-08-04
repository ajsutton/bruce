import SwiftUI

struct HomeAssistantEVOperationalStatusView: View {
  let activity: HomeAssistantEVChargingActivity
  let decisionPresentation: EVChargingDecisionPresentation
  let isActivityLive: Bool
  let isDecisionLive: Bool
  let isLoading: Bool
  var isRefreshing = false
  let mode: BruceMode

  private var copy: EVChargingCopy {
    EVChargingCopy(mode: mode)
  }

  @ViewBuilder
  var body: some View {
    if mode.isFullBruce {
      statusLabel
        .font(.subheadline.weight(.bold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(mode.accentColor.opacity(0.16), in: Capsule())
    } else {
      statusLabel
        .font(.subheadline.weight(.medium))
    }
  }

  private var statusLabel: some View {
    Label {
      Text(statusText)
    } icon: {
      Image(systemName: statusIcon)
        .foregroundStyle(statusColor)
    }
    .foregroundStyle(foreground)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(copy.chargerStatus)
    .accessibilityValue(accessibilityValue)
  }

  private var presentation: HomeAssistantEVActivityPresentation {
    HomeAssistantEVActivityPresentation(activity: activity, mode: mode)
  }

  private var statusText: String {
    if isLoading, !isActivityLive, !isDecisionLive {
      return copy.checkingChargerStatus
    }
    if isRefreshing, activity != .unavailable {
      return copy.updating(lastKnown: presentation.text)
    }
    if displaysDecisionExplanation {
      return displayedText
    }
    if isActivityLive { return displayedText }
    if activity != .unavailable {
      return copy.lastKnown(presentation.text)
    }
    return copy.chargerStatusUnavailable
  }

  private var accessibilityValue: String {
    if isLoading, !isActivityLive, !isDecisionLive {
      return copy.checkingChargerStatus
    }
    if isRefreshing, activity != .unavailable {
      return copy.updating(lastKnown: presentation.accessibilityText)
    }
    if displaysDecisionExplanation {
      return displayedText
    }
    if isActivityLive { return displayedText }
    if activity != .unavailable {
      return copy.lastKnown(presentation.accessibilityText)
    }
    return copy.unavailable
  }

  private var statusIcon: String {
    if isLoading, !isActivityLive, !isDecisionLive {
      return "arrow.clockwise"
    }
    if isRefreshing, activity != .unavailable {
      return "arrow.clockwise"
    }
    return isActivityLive || isDecisionLive ? displayedIcon : "questionmark.circle"
  }

  private var statusColor: Color {
    isRefreshing ? .secondary : (isActivityLive || isDecisionLive ? displayedColor : .secondary)
  }

  private var displaysHeldReason: Bool {
    guard isDecisionLive, decisionPresentation.intent == .held else { return false }
    switch activity {
    case .charging, .complete, .notPluggedIn, .waitingForVehicle:
      return false
    case .connected, .paused, .switchedOff:
      return true
    case .unavailable:
      return false
    }
  }

  private var displaysDecisionExplanation: Bool {
    displaysHeldReason
  }

  private var displayedText: String {
    displaysDecisionExplanation ? decisionPresentation.explanation : presentation.text
  }

  private var displayedIcon: String {
    displaysDecisionExplanation ? decisionPresentation.intent.icon : presentation.statusIcon
  }

  private var displayedColor: Color {
    guard displaysDecisionExplanation else { return presentation.color }
    return switch decisionPresentation.intent {
    case .allowed: .green
    case .held: .orange
    case .unavailable: .secondary
    }
  }

  private var foreground: AnyShapeStyle {
    mode.isFullBruce ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
  }
}

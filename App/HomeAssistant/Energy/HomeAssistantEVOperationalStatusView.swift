import SwiftUI

struct HomeAssistantEVOperationalStatusView: View {
  let activity: HomeAssistantEVChargingActivity
  let isLive: Bool
  let isLoading: Bool
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
    if isLoading, !isLive {
      return copy.checkingChargerStatus
    }
    if isLive {
      return presentation.text
    }
    if activity != .unavailable {
      return copy.lastKnown(presentation.text)
    }
    return copy.chargerStatusUnavailable
  }

  private var accessibilityValue: String {
    if isLoading, !isLive {
      return copy.checkingChargerStatus
    }
    if isLive {
      return presentation.accessibilityText
    }
    if activity != .unavailable {
      return copy.lastKnown(presentation.accessibilityText)
    }
    return copy.unavailable
  }

  private var statusIcon: String {
    if isLoading, !isLive {
      return "arrow.clockwise"
    }
    return isLive ? presentation.statusIcon : "questionmark.circle"
  }

  private var statusColor: Color {
    isLive ? presentation.color : .secondary
  }

  private var foreground: AnyShapeStyle {
    mode.isFullBruce ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
  }
}

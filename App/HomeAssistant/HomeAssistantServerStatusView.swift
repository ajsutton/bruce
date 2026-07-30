import SwiftUI

struct HomeAssistantServerStatusView: View {
  let mode: BruceMode
  let status: HomeAssistantServerStatus
  let isConnecting: Bool
  let isRemovingConnection: Bool

  private var copy: HomeAssistantInterfaceCopy {
    HomeAssistantInterfaceCopy(mode: mode)
  }

  var body: some View {
    TimelineView(
      .periodic(
        from: HomeAssistantServerStatus.nextTimestampRefresh(
          after: .now,
          lastSuccessfulUpdate: status.lastSuccessfulUpdate
        ),
        by: 60
      )
    ) { context in
      platformStatus(at: context.date)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityStatusText(at: context.date))
        .allowsHitTesting(false)
    }
  }

  @ViewBuilder
  private func platformStatus(at date: Date) -> some View {
    #if os(iOS)
      HStack(spacing: 6) {
        Image(systemName: statusIcon)
          .font(.system(size: isHealthyLive ? 7 : 11))
          .foregroundStyle(statusIconColor)
          .accessibilityHidden(true)
          .frame(width: 12, height: 12)

        statusText(at: date)
      }
      .font(.caption)
      .foregroundStyle(foregroundStyle)
      .padding(.horizontal)
      .padding(.vertical, 6)
      .glassEffect()
    #else
      statusText(at: date)
        .font(.caption)
        .foregroundStyle(foregroundStyle)
    #endif
  }

  @ViewBuilder
  private func statusText(at date: Date) -> some View {
    if isRemovingConnection {
      Text(copy.disconnecting)
    } else if isConnecting {
      HStack(spacing: 4) {
        Text(copy.serverConnecting)
        if let lastSuccessfulUpdate = status.lastSuccessfulUpdateForDisplay(at: date) {
          Text("·")
          lastUpdatedText(lastSuccessfulUpdate)
        }
      }
    } else if status.phase == .updating {
      HStack(spacing: 4) {
        Text(copy.serverUpdating)
        if let lastSuccessfulUpdate = status.lastSuccessfulUpdateForDisplay(at: date) {
          Text("·")
          lastUpdatedText(lastSuccessfulUpdate)
        }
      }
    } else if status.phase == .live {
      HStack(spacing: 4) {
        Text(copy.serverLive)
        if let lastSuccessfulUpdate = status.lastSuccessfulUpdateForDisplay(at: date) {
          Text("·")
          lastUpdatedText(lastSuccessfulUpdate)
        }
      }
    }
  }

  private var statusIcon: String {
    if isRemovingConnection {
      return "xmark.circle"
    }
    if isConnecting || status.phase == .updating {
      return "arrow.clockwise"
    }
    return "circle.fill"
  }

  private var statusIconColor: Color {
    isConnecting || isRemovingConnection || status.phase == .updating ? .secondary : .green
  }

  private var isHealthyLive: Bool {
    !isConnecting && !isRemovingConnection && status.phase == .live
  }

  private func accessibilityStatusText(at date: Date) -> Text {
    let title: String
    if isRemovingConnection {
      title = copy.disconnecting
    } else if isConnecting {
      title = copy.serverConnecting
    } else if status.phase == .updating {
      title = copy.serverUpdating
    } else {
      title = copy.serverLiveAccessibility
    }
    guard
      !isRemovingConnection,
      let lastSuccessfulUpdate = status.lastSuccessfulUpdateForDisplay(at: date)
    else {
      return Text(title)
    }
    let timestamp = Text(
      .currentDate,
      format: Date.AnchoredRelativeFormatStyle(
        anchor: lastSuccessfulUpdate,
        presentation: .named,
        unitsStyle: .wide
      )
    )
    return Text("\(Text(title)), \(Text(copy.serverLastChecked)) \(timestamp)")
  }

  private func lastUpdatedText(_ date: Date) -> some View {
    HStack(spacing: 4) {
      Text(copy.serverLastChecked)
      Text(
        .currentDate,
        format: Date.AnchoredRelativeFormatStyle(
          anchor: date,
          presentation: .named,
          unitsStyle: .wide
        )
      )
    }
  }

  private var foregroundStyle: AnyShapeStyle {
    mode.isFullBruce
      ? AnyShapeStyle(Color.white.opacity(0.78))
      : AnyShapeStyle(.secondary)
  }
}

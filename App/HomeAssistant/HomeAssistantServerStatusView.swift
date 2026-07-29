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
    HStack(spacing: 8) {
      Image(systemName: statusIcon)
        .foregroundStyle(statusIconColor)
        .accessibilityHidden(true)
        .frame(width: 16, height: 16)

      statusText
        .font(.caption)
        .foregroundStyle(foregroundStyle)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal)
    .padding(.vertical, 10)
    .background(.bar)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var statusText: some View {
    if isRemovingConnection {
      Text(copy.disconnecting)
    } else if isConnecting {
      HStack(spacing: 4) {
        Text(copy.serverConnecting)
        if let lastSuccessfulUpdate = status.lastSuccessfulUpdate {
          Text("·")
          lastUpdatedText(lastSuccessfulUpdate)
        }
      }
    } else if status.phase == .updating {
      HStack(spacing: 4) {
        Text(copy.serverUpdating)
        if let lastSuccessfulUpdate = status.lastSuccessfulUpdate {
          Text("·")
          lastUpdatedText(lastSuccessfulUpdate)
        }
      }
    } else if status.phase == .live {
      HStack(spacing: 4) {
        Text(copy.serverLive)
        if let lastSuccessfulUpdate = status.lastSuccessfulUpdate {
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
    return "checkmark.circle.fill"
  }

  private var statusIconColor: Color {
    isConnecting || isRemovingConnection || status.phase == .updating ? .secondary : .green
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

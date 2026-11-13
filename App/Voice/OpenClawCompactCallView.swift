import SwiftUI

/// The Mac's active call stays in the main window, directly below its toolbar.
struct OpenClawCompactCallView: View {
  let agent: OpenClawAgent
  let phase: OpenClawVoiceStore.Phase
  let isMuted: Bool
  let mode: BruceMode
  let toggleMute: () -> Void
  let end: () -> Void

  private var copy: VoiceCopy { VoiceCopy(mode: mode) }

  var body: some View {
    HStack(spacing: 12) {
      OpenClawAgentAvatar(agent: agent, size: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(agent.displayName).font(.headline)
          .fixedSize(horizontal: false, vertical: true)
        Text(status).font(.caption).foregroundStyle(.secondary)
          .accessibilityAddTraits(.updatesFrequently)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Button(action: toggleMute) {
        Label(
          isMuted ? copy.unmute : copy.mute, systemImage: isMuted ? "mic.slash.fill" : "mic.fill")
      }
      .labelStyle(.iconOnly)
      .help(isMuted ? copy.unmute : copy.mute)
      .disabled(phase != .connected)
      Button(role: .destructive, action: end) {
        Label(copy.end, systemImage: "phone.down.fill")
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderedProminent)
      .tint(.red)
      .help(copy.end)
      .disabled(phase == .ending)
    }
    .controlSize(.regular)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  private var status: String {
    switch phase {
    case .connected: isMuted ? copy.muted : copy.connected
    case .ending: copy.ending
    case .failed: copy.failed
    case .idle, .loading, .signingIn, .choosing, .connecting: copy.connecting
    }
  }
}

#Preview("Compact call") {
  OpenClawCompactCallView(
    agent: OpenClawAgent(id: "house", name: "Bruce — House", identity: nil),
    phase: .connected, isMuted: false, mode: .standard, toggleMute: {}, end: {}
  )
  .frame(width: 620)
  .background(.bar)
}

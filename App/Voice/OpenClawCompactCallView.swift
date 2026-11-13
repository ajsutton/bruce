import SwiftUI

/// The active Mac call fits within the bottom of the sidebar.
struct OpenClawCompactCallView: View {
  let agent: OpenClawAgent
  let phase: OpenClawVoiceStore.Phase
  let isMuted: Bool
  let mode: BruceMode
  let toggleMute: () -> Void
  let end: () -> Void

  private var copy: VoiceCopy { VoiceCopy(mode: mode) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        OpenClawAgentAvatar(agent: agent, size: 32)
        VStack(alignment: .leading, spacing: 2) {
          Text(agent.displayName).font(.subheadline.bold())
            .fixedSize(horizontal: false, vertical: true)
          Text(status).font(.caption).foregroundStyle(.secondary)
            .accessibilityAddTraits(.updatesFrequently)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        Button(action: toggleMute) {
          Label(
            isMuted ? copy.unmute : copy.mute, systemImage: isMuted ? "mic.slash.fill" : "mic.fill")
        }
        .labelStyle(.iconOnly)
        .help(isMuted ? copy.unmute : copy.mute)
        .disabled(phase != .connected)
        Spacer()
        Button(role: .destructive, action: end) {
          Label(copy.end, systemImage: "phone.down.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(phase == .ending)
      }
    }
    .controlSize(.regular)
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
  .padding(12)
  .frame(width: 200)
  .background(.bar)
}

#Preview("Compact call — narrow Full Bruce") {
  OpenClawCompactCallView(
    agent: OpenClawAgent(id: "family", name: "Bruce, Brucine & Brucette — Family", identity: nil),
    phase: .connected, isMuted: true, mode: .full, toggleMute: {}, end: {}
  )
  .padding(12)
  .frame(width: 170)
  .background(.bar)
}

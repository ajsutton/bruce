import SwiftUI

struct OpenClawCallView: View {
  let agent: OpenClawAgent
  let isConnected: Bool
  let isMuted: Bool
  let mode: BruceMode
  let toggleMute: () -> Void
  let end: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var copy: VoiceCopy { VoiceCopy(mode: mode) }

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        OpenClawAgentAvatar(agent: agent, size: dynamicTypeSize.isAccessibilitySize ? 88 : 144)
        VStack(spacing: 8) {
          Text(agent.displayName).font(.title2.bold()).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
          Text(status).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.updatesFrequently)
          if !isConnected { ProgressView() }
        }
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 24) {
            muteButton
            endButton
          }
          .fixedSize(horizontal: true, vertical: false)
          VStack(spacing: 16) {
            muteButton
            endButton
          }
        }
      }
      .padding(.vertical)
      .frame(maxWidth: .infinity)
    }
  }

  private var muteButton: some View {
    Button(action: toggleMute) {
      Label(isMuted ? copy.unmute : copy.mute, systemImage: isMuted ? "mic.slash.fill" : "mic.fill")
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 80, minHeight: 44)
    }
    .buttonStyle(.bordered)
    .disabled(!isConnected)
  }

  private var endButton: some View {
    Button(role: .destructive, action: end) {
      Label(copy.end, systemImage: "phone.down.fill")
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 80, minHeight: 44)
    }
    .buttonStyle(.borderedProminent)
    .tint(.red)
  }

  private var status: String {
    if !isConnected { return copy.connecting }
    return isMuted ? copy.muted : copy.connected
  }
}

#Preview("Voice call") {
  OpenClawCallView(
    agent: OpenClawAgent(id: "bruce", name: "Bruce", identity: nil),
    isConnected: true, isMuted: false, mode: .standard, toggleMute: {}, end: {}
  )
  .padding(24)
  .frame(width: 380, height: 440)
}

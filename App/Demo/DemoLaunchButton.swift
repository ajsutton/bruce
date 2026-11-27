import SwiftUI

struct DemoLaunchButton: View {
  @Environment(\.bruceVoiceStore) private var voiceStore
  let launch: () -> Void
  let mode: BruceMode

  var body: some View {
    if let voiceStore {
      VoiceSafeDemoButton(store: voiceStore, launch: launch, copy: DemoCopy(mode: mode))
    } else {
      Button(DemoCopy(mode: mode).launch, systemImage: "house", action: launch)
    }
  }
}

private struct VoiceSafeDemoButton: View {
  @ObservedObject var store: OpenClawVoiceStore
  let launch: () -> Void

  let copy: DemoCopy

  private var canLaunch: Bool {
    store.phase == .idle || store.phase == .choosing || store.phase == .failed
  }

  var body: some View {
    Button(copy.launch, systemImage: "house") {
      if canLaunch { launch() }
    }
    .disabled(!canLaunch)
    .accessibilityHint(
      canLaunch ? copy.launchHint : copy.finishVoiceHint
    )
  }
}

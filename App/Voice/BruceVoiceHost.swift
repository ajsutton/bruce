import SwiftUI

struct BruceVoiceHost<Content: View>: View {
  @ObservedObject var store: OpenClawVoiceStore
  let mode: BruceMode
  @ViewBuilder let content: () -> Content
  @State private var showsVoice = false

  var body: some View {
    content()
      .environment(
        \.bruceVoicePresentation, BruceVoicePresentation(store: store, isPresented: $showsVoice)
      )
      #if os(macOS)
        .safeAreaInset(edge: .top, spacing: 0) {
          if let agent = store.agent, store.phase != .idle, store.phase != .choosing {
            OpenClawCompactCallView(
              agent: agent, phase: store.phase, isMuted: store.isMuted, mode: mode,
              toggleMute: store.toggleMute, end: store.end
            )
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
          }
        }
      #else
        .sheet(isPresented: $showsVoice) {
          BruceVoiceView(store: store, mode: mode)
        }
      #endif
      .onChange(of: store.phase) { _, phase in
        if phase == .idle { showsVoice = false }
        #if os(macOS)
          if store.hasCall { showsVoice = false }
        #endif
      }
      .onChange(of: showsVoice) { wasPresented, isPresented in
        if wasPresented, !isPresented { voiceDismissed() }
      }
  }

  private func voiceDismissed() {
    if !store.hasCall, store.phase != .idle, store.phase != .failed { store.end() }
  }
}

#Preview("Voice toolbar") {
  BruceVoiceHost(store: OpenClawVoiceStore(), mode: .standard) {
    NavigationStack {
      Color.clear
        .navigationTitle("Bruce")
        .modifier(BruceVoiceToolbar(mode: .standard))
    }
    .frame(width: 620, height: 360)
  }
}

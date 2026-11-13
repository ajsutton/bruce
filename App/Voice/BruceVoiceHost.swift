import SwiftUI

struct BruceVoiceHost<Content: View>: View {
  @ObservedObject var store: OpenClawVoiceStore
  let mode: BruceMode
  @ViewBuilder let content: () -> Content
  @State private var showsVoice = false

  private var copy: VoiceCopy { VoiceCopy(mode: mode) }

  var body: some View {
    content()
      .safeAreaInset(edge: .bottom) {
        HStack {
          Spacer()
          Button {
            showsVoice = true
            store.prepare()
          } label: {
            Label(store.hasCall ? copy.returnToCall : copy.title, systemImage: "waveform")
              .padding(.horizontal, 8)
              .frame(minHeight: 44)
          }
          .buttonStyle(.borderedProminent)
          .disabled(store.phase == .ending)
          .padding(12)
          Spacer()
        }
        .background(.bar)
      }
      .sheet(isPresented: $showsVoice, onDismiss: voiceDismissed) {
        BruceVoiceView(store: store, mode: mode)
      }
      .onChange(of: store.phase) { _, phase in
        if phase == .idle { showsVoice = false }
      }
  }
  private func voiceDismissed() {
    if !store.hasCall { store.end() }
  }
}

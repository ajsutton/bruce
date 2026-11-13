import SwiftUI

struct BruceVoiceSidebar: ViewModifier {
  @Environment(\.bruceVoiceStore) private var store
  let mode: BruceMode

  func body(content: Content) -> some View {
    content.safeAreaInset(edge: .bottom, spacing: 0) {
      if let store {
        BruceVoiceSidebarView(store: store, mode: mode)
          .padding(12)
          .frame(maxWidth: .infinity)
          .background(.bar)
          .overlay(alignment: .top) { Divider() }
      }
    }
  }
}

private struct BruceVoiceSidebarView: View {
  @ObservedObject var store: OpenClawVoiceStore
  let mode: BruceMode
  @State private var showsPicker = false
  @State private var presenterID = UUID()
  private var copy: VoiceCopy { VoiceCopy(mode: mode) }

  private var buttonTitle: String {
    guard store.phase == .failed else { return copy.title }
    return store.problem == .microphone ? copy.title : copy.retry
  }

  var body: some View {
    Group {
      if let agent = store.agent, store.hasCall || store.phase == .ending {
        OpenClawCompactCallView(
          agent: agent, phase: store.phase, isMuted: store.isMuted, mode: mode,
          toggleMute: store.toggleMute, end: store.end
        )
      } else {
        VStack(spacing: 8) {
          if store.phase == .failed { Text(copy.failed).font(.caption).foregroundStyle(.secondary) }
          Button {
            store.presentPicker(id: presenterID)
            showsPicker = true
            if store.phase == .idle || (store.phase == .failed && store.problem != .microphone) {
              store.prepare()
            }
          } label: {
            Label(buttonTitle, systemImage: "waveform")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }
      }
    }
    #if os(macOS)
      .popover(isPresented: $showsPicker, arrowEdge: .trailing) {
        BruceVoiceView(store: store, mode: mode)
      }
    #endif
    .onChange(of: store.phase) { _, phase in
      if store.hasCall || phase == .idle { showsPicker = false }
    }
    .onChange(of: showsPicker) { wasPresented, isPresented in
      if wasPresented, !isPresented {
        BruceVoicePresentation.dismissPicker(store, presenterID: presenterID)
      }
    }
    .onDisappear { BruceVoicePresentation.dismissPicker(store, presenterID: presenterID) }
  }
}

#Preview("Sidebar voice button") {
  Color.clear
    .modifier(BruceVoiceSidebar(mode: .standard))
    .environment(\.bruceVoiceStore, OpenClawVoiceStore())
    .frame(width: 220, height: 320)
}

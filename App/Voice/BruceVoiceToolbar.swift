import SwiftUI

struct BruceVoicePresentation {
  let store: OpenClawVoiceStore
  let isPresented: Binding<Bool>
}

extension EnvironmentValues {
  @Entry var bruceVoicePresentation: BruceVoicePresentation?
}

struct BruceVoiceToolbar: ViewModifier {
  @Environment(\.bruceVoicePresentation) private var presentation
  let mode: BruceMode
  var isAvailable = true

  func body(content: Content) -> some View {
    content.toolbar {
      if isAvailable, let presentation {
        ToolbarItem(placement: .primaryAction) {
          BruceVoiceToolbarButton(
            store: presentation.store, isPresented: presentation.isPresented, mode: mode
          )
        }
      }
    }
  }
}

private struct BruceVoiceToolbarButton: View {
  @ObservedObject var store: OpenClawVoiceStore
  @Binding var isPresented: Bool
  let mode: BruceMode

  private var copy: VoiceCopy { VoiceCopy(mode: mode) }

  var body: some View {
    Button {
      isPresented = true
      if store.phase == .idle { store.prepare() }
    } label: {
      Label(store.hasCall ? copy.returnToCall : copy.title, systemImage: "waveform")
    }
    .labelStyle(.iconOnly)
    .help(helpText)
    .disabled(isDisabled)
    #if os(macOS)
      .popover(isPresented: $isPresented, arrowEdge: .bottom) {
        BruceVoiceView(store: store, mode: mode)
      }
    #endif
  }

  private var helpText: String {
    switch store.phase {
    case .connecting: copy.connecting
    case .connected: copy.connected
    case .ending: copy.ending
    case .failed: copy.failed
    case .idle, .loading, .signingIn, .choosing: copy.title
    }
  }

  private var isDisabled: Bool {
    #if os(macOS)
      store.phase == .ending || store.hasCall
    #else
      store.phase == .ending
    #endif
  }
}

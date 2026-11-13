import SwiftUI

struct BruceVoiceHost<Content: View>: View {
  let store: OpenClawVoiceStore
  @ViewBuilder let content: () -> Content

  var body: some View {
    content().environment(\.bruceVoiceStore, store)
  }
}

extension EnvironmentValues {
  @Entry var bruceVoiceStore: OpenClawVoiceStore?
}

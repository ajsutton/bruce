import SwiftUI

struct BruceVoiceDestinationView: View {
  @Environment(\.bruceVoiceStore) private var store
  let mode: BruceMode

  var body: some View {
    if let store {
      BruceVoiceView(store: store, mode: mode, isEmbedded: true)
    } else {
      ContentUnavailableView(VoiceCopy(mode: mode).title, systemImage: "waveform")
    }
  }
}

#Preview("Voice destination") {
  BruceVoiceDestinationView(mode: .standard)
    .environment(\.bruceVoiceStore, OpenClawVoiceStore(client: PreviewVoiceDestinationClient()))
}

@MainActor
private final class PreviewVoiceDestinationClient: OpenClawVoiceServing {
  var onDisconnect: (() -> Void)?

  func agents(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws
    -> [OpenClawAgent]
  {
    [
      OpenClawAgent(id: "house", name: "Bruce — House", identity: nil),
      OpenClawAgent(id: "family", name: "Bruce — Family", identity: nil),
    ]
  }

  func start(agentID: String, offer: String) async throws -> String {
    throw OpenClawVoiceError.unavailable
  }
  func connected() {}
  func close() async throws {}
}

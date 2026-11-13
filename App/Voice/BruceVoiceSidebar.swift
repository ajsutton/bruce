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
  @State private var presenterID = UUID()
  @Environment(\.openURL) private var openURL
  private var copy: VoiceCopy { VoiceCopy(mode: mode) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let agent = store.agent, store.hasCall || store.phase == .ending {
        OpenClawCompactCallView(
          agent: agent, phase: store.phase, isMuted: store.isMuted, mode: mode,
          toggleMute: store.toggleMute, end: { store.end() }
        )
      } else if store.phase == .idle {
        Button {
          store.prepare()
        } label: {
          Label(copy.title, systemImage: "waveform").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      } else {
        HStack(alignment: .top) {
          Text(copy.title).font(.headline)
          Spacer(minLength: 4)
          if store.phase == .choosing {
            Button(action: store.refreshAgents) { Image(systemName: "arrow.clockwise") }
              .help(copy.refreshAgents)
              .accessibilityLabel(copy.refreshAgents)
          }
          Button(action: { store.end() }, label: { Image(systemName: "xmark") })
            .labelStyle(.iconOnly)
            .help(copy.done)
            .accessibilityLabel(copy.done)
            .disabled(store.phase == .ending)
        }
        preparation
      }
    }
    .onAppear { store.presentPicker(id: presenterID) }
    .onDisappear { BruceVoicePresentation.dismissPicker(store, presenterID: presenterID) }
    #if os(macOS)
      .onChange(of: store.browser?.id, initial: true) {
        if let browser = store.browser, store.claimBrowserLaunch(id: browser.id) {
          NSWorkspace.shared.open(browser.url)
        }
      }
    #endif
  }

  @ViewBuilder private var preparation: some View {
    switch store.phase {
    case .choosing:
      if store.agents.isEmpty {
        Text(copy.empty).font(.caption).foregroundStyle(.secondary)
      } else {
        ScrollView {
          VStack(spacing: 8) {
            ForEach(store.agents) { agent in
              Button {
                store.start(agent)
              } label: {
                HStack(spacing: 8) {
                  OpenClawAgentAvatar(agent: agent, size: 28)
                  Text(agent.displayName).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(6)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityHint(copy.startHint)
            }
          }
        }
        .frame(height: min(CGFloat(store.agents.count) * 64, 220))
      }
    case .signingIn:
      Text(copy.signInDescription).font(.caption).foregroundStyle(.secondary)
      if let browser = store.browser, browser.isWebsite {
        Button(copy.continueSignIn) {
          store.continueSignIn(browserID: browser.id)
        }
      }
    case .failed:
      Text(copy.message(store.problem)).font(.caption).foregroundStyle(.secondary)
      if store.problem == .microphone {
        Button(copy.openSettings) {
          if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
          {
            openURL(url)
          }
        }
      } else {
        Button(copy.retry) {
          store.prepare()
        }
      }
    case .loading:
      Text(copy.loading).font(.caption).foregroundStyle(.secondary)
    case .ending:
      Text(copy.ending).font(.caption).foregroundStyle(.secondary)
    case .idle, .connecting, .connected:
      EmptyView()
    }
  }
}

#Preview("Sidebar voice button") {
  Color.clear
    .modifier(BruceVoiceSidebar(mode: .standard))
    .environment(\.bruceVoiceStore, OpenClawVoiceStore())
    .frame(width: 220, height: 320)
}

#Preview("Sidebar voice choosing — narrow") {
  PreviewVoiceSidebarChoosing()
}

@MainActor
private struct PreviewVoiceSidebarChoosing: View {
  @StateObject private var store = OpenClawVoiceStore(client: PreviewVoiceSidebarClient())

  var body: some View {
    Color.clear
      .modifier(BruceVoiceSidebar(mode: .standard))
      .environment(\.bruceVoiceStore, store)
      .frame(width: 170, height: 360)
      .task {
        if store.phase == .idle { store.prepare() }
      }
  }
}

@MainActor
private final class PreviewVoiceSidebarClient: OpenClawVoiceServing {
  var onDisconnect: (() -> Void)?

  func agents(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws
    -> [OpenClawAgent]
  {
    [
      OpenClawAgent(id: "house", name: "Bruce — House", identity: nil),
      OpenClawAgent(
        id: "family", name: "Bruce, Brucine & Brucette — Family", identity: nil),
    ]
  }

  func connect(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws {}

  func start(agentID: String, offer: String) async throws -> String {
    throw OpenClawVoiceError.unavailable
  }

  func connected() {}
  func close() async throws {}
}

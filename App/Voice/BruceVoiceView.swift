import SwiftUI

struct BruceVoiceView: View {
  @ObservedObject var store: OpenClawVoiceStore
  let mode: BruceMode
  var isEmbedded = false
  @Environment(\.colorScheme) private var colorScheme
  @State private var showsProgress = false
  @Environment(\.openURL) private var openURL
  @Environment(\.dismiss) private var dismiss

  private var copy: VoiceCopy { VoiceCopy(mode: mode) }

  var body: some View {
    NavigationStack {
      content
        .safeAreaInset(edge: .bottom) {
          if let url = URL(string: "https://bruce.symphonious.net/privacy/") {
            Link(copy.privacy, destination: url).font(.footnote).padding(.vertical, 8)
          }
        }
        .navigationTitle(isEmbedded ? AppCopy(mode: mode).voiceTab : copy.title)
        .toolbar {
          if !isEmbedded {
            ToolbarItem(placement: .cancellationAction) {
              Button(store.hasCall ? copy.hideCall : copy.done) { dismiss() }
                .accessibilityHint(store.hasCall ? copy.hideCallHint : "")
            }
          }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(mode.panelBackgroundColor(for: colorScheme))
    }
    .tint(mode.accentColor)
    .interactiveDismissDisabled(!isEmbedded && store.hasCall)
    .onAppear {
      if isEmbedded, store.phase == .idle || store.phase == .ending { store.prepare() }
    }
    .task(id: store.phase) {
      showsProgress = false
      guard store.phase == .loading || store.phase == .ending else { return }
      do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
      showsProgress = true
    }
    #if os(macOS)
      .frame(minWidth: 360, idealWidth: 420, minHeight: 380, idealHeight: 480)
      .onChange(of: store.browser?.id, initial: true) {
        if let browser = store.browser { NSWorkspace.shared.open(browser.url) }
      }
    #else
      .sheet(item: $store.browser, onDismiss: store.browserDismissed) { browser in
        OpenClawSignInBrowser(url: browser.url) { store.browser = nil }
        .interactiveDismissDisabled()
      }
    #endif
  }

  @ViewBuilder private var content: some View {
    switch store.phase {
    case .choosing:
      if store.agents.isEmpty {
        ContentUnavailableView(copy.empty, systemImage: "person.crop.circle")
      } else {
        OpenClawAgentPickerView(agents: store.agents, mode: mode, select: store.start)
      }
    case .connecting, .connected:
      if let agent = store.agent {
        OpenClawCallView(
          agent: agent, isConnected: store.phase == .connected, isMuted: store.isMuted,
          mode: mode, toggleMute: store.toggleMute, end: { store.end() }
        )
      }
    case .signingIn:
      VStack(spacing: 20) {
        Image(systemName: "person.crop.circle.badge.checkmark").font(.largeTitle)
        Text(copy.signIn).font(.title2)
        Text(copy.signInDescription).multilineTextAlignment(.center)
        #if os(macOS)
          if let browser = store.browser, browser.isWebsite {
            Button(copy.continueSignIn) {
              store.continueSignIn(browserID: browser.id)
            }
            .buttonStyle(.borderedProminent)
          } else {
            ProgressView()
          }
        #else
          ProgressView()
        #endif
      }
    case .failed:
      ContentUnavailableView {
        Label(copy.failed, systemImage: "phone.down")
      } description: {
        Text(copy.message(store.problem))
      } actions: {
        if store.problem == .microphone {
          Button(copy.openSettings, action: openMicrophoneSettings).buttonStyle(.borderedProminent)
        } else {
          Button(copy.retry, action: store.prepare).buttonStyle(.borderedProminent)
        }
      }
    case .idle:
      Button(action: store.prepare) {
        Label(copy.title, systemImage: "waveform")
      }
      .buttonStyle(.borderedProminent)
    case .loading, .ending:
      VStack(spacing: 16) {
        ProgressView().opacity(showsProgress ? 1 : 0)
        Text(store.phase == .ending ? copy.ending : copy.loading)
      }
    }
  }
  private func openMicrophoneSettings() {
    #if os(iOS)
      let address = UIApplication.openSettingsURLString
    #else
      let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    #endif
    if let url = URL(string: address) { openURL(url) }
  }

}

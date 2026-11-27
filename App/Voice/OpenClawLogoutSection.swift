import Accessibility
import SwiftUI

struct OpenClawLogoutSection: View {
  @ObservedObject var store: OpenClawVoiceStore
  let mode: BruceMode
  @State private var logoutRequested = false
  @State private var didLogOut = false
  @State private var didFail = false

  private var copy: VoiceCopy { VoiceCopy(mode: mode) }

  var body: some View {
    Section {
      Button(copy.logOut, role: .destructive) { logoutRequested = true }
        .accessibilityIdentifier(BruceAccessibilityIdentifier.openClawLogout)
        .disabled(logoutRequested || store.isLoggingOut)
      if store.isLoggingOut {
        Text(copy.loggingOut).foregroundStyle(.secondary)
      } else if didFail {
        Text(copy.logoutFailed).foregroundStyle(.red)
      } else if didLogOut {
        Text(copy.loggedOut).foregroundStyle(.secondary)
          .accessibilityIdentifier(BruceAccessibilityIdentifier.openClawLoggedOut)
      }
    } header: {
      Text(verbatim: "OpenClaw")
    } footer: {
      Text(copy.logoutExplanation)
    }
    .task(id: logoutRequested) {
      guard logoutRequested else { return }
      didLogOut = false
      didFail = false
      do {
        try await store.logOut()
        didLogOut = true
        AccessibilityNotification.Announcement(copy.loggedOut).post()
      } catch {
        didFail = true
        AccessibilityNotification.Announcement(copy.logoutFailed).post()
      }
      logoutRequested = false
    }
    .onChange(of: store.isLoggingOut) { _, isLoggingOut in
      if isLoggingOut { AccessibilityNotification.Announcement(copy.loggingOut).post() }
    }
    .onChange(of: store.phase) { _, phase in
      if phase == .loading || phase == .signingIn {
        didLogOut = false
        didFail = false
      }
    }
  }
}

#Preview("OpenClaw logout") {
  Form {
    OpenClawLogoutSection(store: OpenClawVoiceStore(), mode: .standard)
  }
  .formStyle(.grouped)
}

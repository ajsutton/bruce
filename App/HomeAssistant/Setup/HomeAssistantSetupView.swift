import Accessibility
import AuthenticationServices
import SwiftUI

struct HomeAssistantSetupView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession
  @ObservedObject var store: HomeAssistantSetupStore
  let mode: BruceMode
  var startsInConnectionManagement = false
  @State private var webAuthenticationOwnerID = UUID()
  @State private var showsAuthenticationTechnicalDetails = false
  @State private var showsDisconnectConfirmation = false
  @State private var showsRestoreRemovalConfirmation = false

  private var setupCopy: HomeAssistantSetupCopy {
    HomeAssistantSetupCopy(mode: mode)
  }

  private var interfaceCopy: HomeAssistantInterfaceCopy {
    HomeAssistantInterfaceCopy(mode: mode)
  }

  var body: some View {
    NavigationStack {
      Group {
        #if os(iOS)
          HomeAssistantSetupPresentationView(
            store: store,
            mode: mode,
            startsInConnectionManagement: startsInConnectionManagement,
            reauthenticate: beginReauthentication
          ) {
            setupContent
          }
        #else
          setupContent
        #endif
      }
      .navigationTitle(setupCopy.navigationTitle)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          if startsInConnectionManagement {
            ToolbarItem(placement: .confirmationAction) {
              Button(interfaceCopy.done) {
                dismiss()
              }
            }
          }
        }
      #endif
    }
    .onAppear {
      #if os(macOS)
        registerWebAuthenticationAction()
      #endif
    }
    .onDisappear {
      store.stopDiscovery()
      store.unregisterWebAuthenticationAction(ownerID: webAuthenticationOwnerID)
    }
    #if os(macOS)
      .onChange(of: store.connectionCheckState) { _, state in
        if let announcement = setupCopy.connectionCheckAnnouncement(state) {
          AccessibilityNotification.Announcement(announcement).post()
        }
      }
      .onChange(of: store.isDisconnecting) { _, isDisconnecting in
        if isDisconnecting {
          AccessibilityNotification.Announcement(interfaceCopy.disconnectingAccessibility).post()
        }
      }
    #endif
    .confirmationDialog(
      interfaceCopy.disconnectQuestion,
      isPresented: $showsDisconnectConfirmation
    ) {
      Button(interfaceCopy.disconnect, role: .destructive) {
        store.disconnect()
      }
      Button(interfaceCopy.cancel, role: .cancel) {}
    } message: {
      Text(interfaceCopy.disconnectExplanation)
    }
    .confirmationDialog(
      interfaceCopy.removeConnectionQuestion,
      isPresented: $showsRestoreRemovalConfirmation
    ) {
      Button(interfaceCopy.removeConnection, role: .destructive) {
        store.disconnect()
      }
      Button(interfaceCopy.cancel, role: .cancel) {}
    } message: {
      Text(interfaceCopy.disconnectExplanation)
    }
  }

  private func beginAuthentication(retrying: Bool = false) {
    #if os(iOS)
      registerWebAuthenticationAction()
    #endif
    if retrying {
      store.retryAuthentication()
    } else {
      store.requestAuthentication()
    }
  }

  private func registerWebAuthenticationAction() {
    let authenticationSession = webAuthenticationSession
    store.registerWebAuthenticationAction(ownerID: webAuthenticationOwnerID) { url in
      try await authenticationSession.authenticate(
        using: url,
        callback: .https(host: "bruce.symphonious.net", path: "/auth/"),
        preferredBrowserSession: nil,
        additionalHeaderFields: [:]
      )
    }
  }

  private func beginReauthentication() {
    registerWebAuthenticationAction()
    store.reauthenticate()
  }

  private var setupContent: some View {
    HomeAssistantSetupContentView(
      store: store,
      mode: mode,
      showsAuthenticationTechnicalDetails: $showsAuthenticationTechnicalDetails,
      showsDisconnectConfirmation: $showsDisconnectConfirmation,
      showsRestoreRemovalConfirmation: $showsRestoreRemovalConfirmation,
      beginAuthentication: beginAuthentication,
      beginReauthentication: beginReauthentication
    )
  }
}

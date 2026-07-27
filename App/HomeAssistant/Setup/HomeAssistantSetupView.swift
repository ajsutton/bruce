import Accessibility
import AuthenticationServices
import SwiftUI

struct HomeAssistantSetupView: View {
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession
  @ObservedObject var store: HomeAssistantSetupStore
  let mode: BruceMode
  @State private var webAuthenticationOwnerID = UUID()
  @State private var showsAuthenticationTechnicalDetails = false
  @State private var showsDisconnectConfirmation = false
  @State private var showsRestoreRemovalConfirmation = false

  private var copy: HomeAssistantCopy {
    HomeAssistantCopy(mode: mode)
  }

  var body: some View {
    NavigationStack {
      Group {
        switch store.step {
        case .restoring:
          HomeAssistantRestoringView(
            store: store,
            title: copy.restoringTitle,
            detail: copy.restoringDetail,
            requestRemoval: {
              showsRestoreRemovalConfirmation = true
            }
          )
        case .restoreFailed:
          restoreFailed
        case .introduction:
          introduction
        case .chooseServer:
          HomeAssistantServerChoiceView(store: store, copy: copy)
        case .manualEntry:
          HomeAssistantManualEntryView(store: store, copy: copy)
        case .confirmation(let candidate):
          confirmation(candidate)
        case .unencryptedWarning(let candidate):
          unencryptedWarning(candidate)
        case .onboardingRequired(let instance):
          onboardingRequired(instance)
        case .readyForAuthentication(let candidate):
          authenticationHandoff(candidate)
        case .authenticationFailed(_, let failure):
          HomeAssistantAuthenticationFailureView(
            copy: copy,
            failure: failure,
            showsTechnicalDetails: $showsAuthenticationTechnicalDetails,
            retry: { beginAuthentication(retrying: true) },
            chooseAnotherServer: store.showDiscoveredHomes
          )
        case .configured(let credentials):
          configured(credentials)
        case .connected(let credentials):
          connected(credentials)
        case .cancelled:
          cancelled
        }
      }
      .navigationTitle(copy.navigationTitle)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
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
        if let announcement = copy.connectionCheckAnnouncement(state) {
          AccessibilityNotification.Announcement(announcement).post()
        }
      }
      .onChange(of: store.isDisconnecting) { _, isDisconnecting in
        if isDisconnecting {
          AccessibilityNotification.Announcement("Disconnecting from Home Assistant").post()
        }
      }
    #endif
    .confirmationDialog(
      "Disconnect from Home Assistant?",
      isPresented: $showsDisconnectConfirmation
    ) {
      Button("Disconnect", role: .destructive) {
        store.disconnect()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Bruce will remove the saved Home Assistant connection from this device.")
    }
    .confirmationDialog(
      "Remove Home Assistant Connection?",
      isPresented: $showsRestoreRemovalConfirmation
    ) {
      Button("Remove Connection", role: .destructive) {
        store.disconnect()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Bruce will remove the saved Home Assistant connection from this device.")
    }
  }
}

extension HomeAssistantSetupView {
  private var introduction: some View {
    scrollableState {
      ContentUnavailableView {
        Label(copy.introductionTitle, systemImage: "house.and.flag.fill")
      } description: {
        Text(copy.introductionDescription)
      } actions: {
        Button(copy.findHomeAssistant) {
          store.startDiscovery()
        }
        .buttonStyle(.borderedProminent)

        Button(copy.enterAddressManually) {
          store.showManualEntry()
        }
      }
      .padding()
    }
  }

  private func confirmation(_ candidate: HomeAssistantConnectionCandidate) -> some View {
    Form {
      Section("Home") {
        LabeledContent("Name", value: candidate.name)
        LabeledContent("Address", value: candidate.activeURL.absoluteString)
      }

      Section {
        Button("Sign In to Home Assistant") {
          beginAuthentication()
        }
        .buttonStyle(.borderedProminent)

        Button(copy.chooseAnotherServer) {
          store.showDiscoveredHomes()
        }
      }
    }
    .formStyle(.grouped)
  }

  private func unencryptedWarning(
    _ candidate: HomeAssistantConnectionCandidate
  ) -> some View {
    scrollableState {
      ContentUnavailableView {
        Label(copy.unencryptedTitle, systemImage: "exclamationmark.triangle.fill")
      } description: {
        Text(copy.unencryptedMessage)
      } actions: {
        Button("Continue with HTTP") {
          store.acceptUnencryptedConnection()
        }
        .buttonStyle(.borderedProminent)

        Button("Go Back", role: .cancel) {
          store.rejectUnencryptedConnection()
        }
      }
      .padding()
    }
  }

  private func onboardingRequired(_ instance: HomeAssistantInstance) -> some View {
    scrollableState {
      ContentUnavailableView {
        Label(copy.onboardingTitle, systemImage: "wrench.and.screwdriver.fill")
      } description: {
        Text(copy.onboardingMessage(instanceName: instance.name))
      } actions: {
        Button(copy.recoveryChooseAnotherServer) {
          store.showDiscoveredHomes()
        }
      }
      .padding()
    }
  }

  private func authenticationHandoff(
    _ candidate: HomeAssistantConnectionCandidate
  ) -> some View {
    scrollableState {
      ContentUnavailableView {
        Label(copy.openingHomeAssistant, systemImage: "person.badge.key.fill")
      } description: {
        Text(copy.authenticationHandoff(instanceName: candidate.name))
      } actions: {
        Button("Cancel", role: .cancel) {
          store.cancelAuthentication()
        }
      }
      .padding()
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

  private func connected(_ credentials: HomeAssistantCredentials) -> some View {
    Form {
      Section {
        Label(
          copy.connectedTitle(instanceName: credentials.instanceName),
          systemImage: "checkmark.circle.fill"
        )
        connectionOverviewDetails(credentials)
      } footer: {
        connectionCheckDescription
      }

      Section {
        connectionManagementControls
      }
    }
    .formStyle(.grouped)
  }

  private func configured(_ credentials: HomeAssistantCredentials) -> some View {
    Form {
      Section {
        Label(
          copy.configuredTitle(instanceName: credentials.instanceName),
          systemImage: "exclamationmark.circle"
        )
        connectionOverviewDetails(credentials)
      } footer: {
        connectionCheckDescription
      }

      Section {
        connectionManagementControls
      }
    }
    .formStyle(.grouped)
  }

  @ViewBuilder
  private var connectionCheckDescription: some View {
    if store.isDisconnecting {
      HStack {
        ProgressView()
          .controlSize(.small)
        Text("Disconnecting from Home Assistant…")
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Disconnecting from Home Assistant")
    } else {
      switch store.connectionCheckState {
      case .idle:
        Text(copy.connectionIdle)
      case .checking:
        Text(copy.connectionChecking)
      case .succeeded:
        Text(copy.connectionSucceeded)
      case .failed(let problem):
        Text(copy.connectionFailed(problem))
      case .reauthenticationRequired:
        Text(copy.reauthenticationRequired)
      case .disconnectFailed:
        Text(copy.disconnectFailed)
      }
    }
  }

  @ViewBuilder
  private func connectionOverviewDetails(_ credentials: HomeAssistantCredentials) -> some View {
    #if os(macOS)
      HomeAssistantConnectionDetails(credentials: credentials)
    #else
      LabeledContent(
        "Last successful route",
        value: credentials.lastSuccessfulURL.absoluteString
      )
    #endif
  }

  @ViewBuilder
  private var connectionManagementControls: some View {
    #if os(macOS)
      Button(copy.testConnection) {
        store.testConnection()
      }
      .disabled(store.connectionCheckState == .checking || store.isDisconnecting)
      .accessibilityValue(store.connectionCheckState == .checking ? "Checking" : "Ready")

      if store.connectionCheckState.canSignInAgain {
        Button("Sign In Again") {
          store.reauthenticate()
        }
        .disabled(store.isDisconnecting)
      }

      Button(copy.changeServer) {
        store.changeServer()
      }
      .disabled(store.isDisconnecting)

      Button(store.connectionCheckState.disconnectButtonTitle, role: .destructive) {
        showsDisconnectConfirmation = true
      }
      .disabled(store.isDisconnecting)
    #else
      NavigationLink(copy.manageConnection) {
        HomeAssistantConnectionManagementView(
          store: store,
          copy: copy,
          reauthenticate: beginReauthentication
        )
      }
    #endif
  }

  private func beginReauthentication() {
    registerWebAuthenticationAction()
    store.reauthenticate()
  }

  private var cancelled: some View {
    scrollableState {
      ContentUnavailableView {
        Label(copy.setupCancelledTitle, systemImage: "xmark.circle")
      } actions: {
        Button(copy.startAgain) {
          store.startDiscovery()
        }
      }
      .padding()
    }
  }

  private var restoreFailed: some View {
    scrollableState {
      ContentUnavailableView {
        Label(copy.restoreFailedTitle, systemImage: "key.slash")
      } description: {
        Text(copy.restoreFailedMessage)
      } actions: {
        Button("Set Up Home Assistant Again") {
          store.changeServer()
        }
      }
      .padding()
    }
  }

  private func scrollableState<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    ScrollView {
      content()
        .frame(maxWidth: .infinity)
    }
  }
}

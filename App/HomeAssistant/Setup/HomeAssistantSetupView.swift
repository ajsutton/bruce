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

  private var setupCopy: HomeAssistantSetupCopy {
    HomeAssistantSetupCopy(mode: mode)
  }

  private var interfaceCopy: HomeAssistantInterfaceCopy {
    HomeAssistantInterfaceCopy(mode: mode)
  }

  var body: some View {
    NavigationStack {
      Group {
        switch store.step {
        case .restoring:
          HomeAssistantRestoringView(
            store: store,
            mode: mode,
            requestRemoval: {
              showsRestoreRemovalConfirmation = true
            }
          )
        case .restoreFailed:
          restoreFailed
        case .introduction:
          introduction
        case .chooseServer:
          HomeAssistantServerChoiceView(store: store, mode: mode)
        case .manualEntry:
          HomeAssistantManualEntryView(store: store, mode: mode)
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
            mode: mode,
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
      .navigationTitle(setupCopy.navigationTitle)
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
}

extension HomeAssistantSetupView {
  private var introduction: some View {
    scrollableState {
      ContentUnavailableView {
        Label(setupCopy.introductionTitle, systemImage: "house.and.flag.fill")
      } description: {
        Text(setupCopy.introductionDescription)
      } actions: {
        Button(setupCopy.findHomeAssistant) {
          store.startDiscovery()
        }
        .buttonStyle(.borderedProminent)

        Button(setupCopy.enterAddressManually) {
          store.showManualEntry()
        }
      }
      .padding()
    }
  }

  private func confirmation(_ candidate: HomeAssistantConnectionCandidate) -> some View {
    Form {
      Section(interfaceCopy.homeSection) {
        LabeledContent(interfaceCopy.nameLabel, value: candidate.name)
        LabeledContent(interfaceCopy.addressLabel, value: candidate.activeURL.absoluteString)
      }

      Section {
        Button(interfaceCopy.signIn) {
          beginAuthentication()
        }
        .buttonStyle(.borderedProminent)

        Button(setupCopy.chooseAnotherServer) {
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
        Label(setupCopy.unencryptedTitle, systemImage: "exclamationmark.triangle.fill")
      } description: {
        Text(setupCopy.unencryptedMessage)
      } actions: {
        Button(interfaceCopy.continueWithHTTP) {
          store.acceptUnencryptedConnection()
        }
        .buttonStyle(.borderedProminent)

        Button(interfaceCopy.goBackFromHTTP, role: .cancel) {
          store.rejectUnencryptedConnection()
        }
      }
      .padding()
    }
  }

  private func onboardingRequired(_ instance: HomeAssistantInstance) -> some View {
    scrollableState {
      ContentUnavailableView {
        Label(setupCopy.onboardingTitle, systemImage: "wrench.and.screwdriver.fill")
      } description: {
        Text(setupCopy.onboardingMessage(instanceName: instance.name))
      } actions: {
        Button(setupCopy.recoveryChooseAnotherServer) {
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
        Label(setupCopy.openingHomeAssistant, systemImage: "person.badge.key.fill")
      } description: {
        Text(setupCopy.authenticationHandoff(instanceName: candidate.name))
      } actions: {
        Button(interfaceCopy.cancel, role: .cancel) {
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
          setupCopy.connectedTitle(instanceName: credentials.instanceName),
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
          setupCopy.configuredTitle(instanceName: credentials.instanceName),
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
        Text(interfaceCopy.disconnecting)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(interfaceCopy.disconnectingAccessibility)
    } else {
      switch store.connectionCheckState {
      case .idle:
        Text(setupCopy.connectionIdle)
      case .checking:
        Text(setupCopy.connectionChecking)
      case .succeeded:
        Text(setupCopy.connectionSucceeded)
      case .failed(let problem):
        Text(setupCopy.connectionFailed(problem))
      case .reauthenticationRequired:
        Text(setupCopy.reauthenticationRequired)
      case .disconnectFailed:
        Text(setupCopy.disconnectFailed)
      }
    }
  }

  @ViewBuilder
  private func connectionOverviewDetails(_ credentials: HomeAssistantCredentials) -> some View {
    #if os(macOS)
      HomeAssistantConnectionDetails(credentials: credentials, copy: interfaceCopy)
    #else
      LabeledContent(
        interfaceCopy.lastSuccessfulRoute,
        value: credentials.lastSuccessfulURL.absoluteString
      )
    #endif
  }

  @ViewBuilder
  private var connectionManagementControls: some View {
    #if os(macOS)
      Button(setupCopy.testConnection) {
        store.testConnection()
      }
      .disabled(store.connectionCheckState == .checking || store.isDisconnecting)
      .accessibilityValue(
        store.connectionCheckState == .checking ? interfaceCopy.checking : interfaceCopy.ready
      )

      if store.connectionCheckState.canSignInAgain {
        Button(interfaceCopy.signInAgain) {
          store.reauthenticate()
        }
        .disabled(store.isDisconnecting)
      }

      Button(setupCopy.changeServer) {
        store.changeServer()
      }
      .disabled(store.isDisconnecting)

      Button(
        interfaceCopy.disconnectButtonTitle(state: store.connectionCheckState),
        role: .destructive
      ) {
        showsDisconnectConfirmation = true
      }
      .disabled(store.isDisconnecting)
    #else
      NavigationLink(setupCopy.manageConnection) {
        HomeAssistantConnectionManagementView(
          store: store,
          mode: mode,
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
        Label(setupCopy.setupCancelledTitle, systemImage: "xmark.circle")
      } actions: {
        Button(setupCopy.startAgain) {
          store.startDiscovery()
        }
      }
      .padding()
    }
  }

  private var restoreFailed: some View {
    scrollableState {
      ContentUnavailableView {
        Label(setupCopy.restoreFailedTitle, systemImage: "key.slash")
      } description: {
        Text(setupCopy.restoreFailedMessage)
      } actions: {
        Button(interfaceCopy.setUpAgain) {
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

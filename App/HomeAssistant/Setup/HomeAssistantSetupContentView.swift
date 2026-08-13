import SwiftUI

struct HomeAssistantSetupContentView: View {
  @ObservedObject var store: HomeAssistantSetupStore
  let mode: BruceMode
  @Binding var showsAuthenticationTechnicalDetails: Bool
  @Binding var showsDisconnectConfirmation: Bool
  @Binding var showsRestoreRemovalConfirmation: Bool
  let beginAuthentication: (Bool) -> Void
  let beginReauthentication: () -> Void

  private var setupCopy: HomeAssistantSetupCopy {
    HomeAssistantSetupCopy(mode: mode)
  }

  private var interfaceCopy: HomeAssistantInterfaceCopy {
    HomeAssistantInterfaceCopy(mode: mode)
  }

  @ViewBuilder
  var body: some View {
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
        retry: { beginAuthentication(true) },
        chooseAnotherServer: store.showDiscoveredHomes
      )
    case .finishingConnection(let credentials):
      finishingConnection(credentials)
    case .connectionFailed(let credentials, let problem):
      connectionFailed(credentials, problem: problem)
    case .configured(let credentials):
      HomeAssistantConnectionSummaryView(
        store: store,
        mode: mode,
        credentials: credentials,
        showsDisconnectConfirmation: $showsDisconnectConfirmation,
        reauthenticate: beginReauthentication
      )
    case .connected(let credentials):
      HomeAssistantConnectionSummaryView(
        store: store,
        mode: mode,
        credentials: credentials,
        showsDisconnectConfirmation: $showsDisconnectConfirmation,
        reauthenticate: beginReauthentication
      )
    case .disconnecting(let credentials):
      HomeAssistantConnectionSummaryView(
        store: store,
        mode: mode,
        credentials: credentials,
        showsDisconnectConfirmation: $showsDisconnectConfirmation,
        reauthenticate: beginReauthentication
      )
    case .cancelled:
      cancelled
    }
  }

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
          beginAuthentication(false)
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

  private func finishingConnection(_ credentials: HomeAssistantCredentials) -> some View {
    scrollableState {
      ContentUnavailableView {
        Label(setupCopy.finishingConnectionTitle, systemImage: "ellipsis.circle")
      } description: {
        Text(setupCopy.finishingConnectionDetail(instanceName: credentials.instanceName))
      }
      .padding()
    }
  }

  private func connectionFailed(
    _ credentials: HomeAssistantCredentials,
    problem: HomeAssistantSetupStore.ConnectionCheckProblem
  ) -> some View {
    scrollableState {
      ContentUnavailableView {
        Label(setupCopy.postAuthenticationFailureTitle, systemImage: "wifi.exclamationmark")
      } description: {
        Text(credentials.instanceName)
          .font(.headline)
        Text(setupCopy.postAuthenticationFailureDetail(problem))
      } actions: {
        Button(interfaceCopy.refreshConnection) {
          store.retryConnection()
        }
        .buttonStyle(.borderedProminent)

        Button(setupCopy.changeServer) {
          store.changeServer()
        }
      }
      .padding()
    }
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

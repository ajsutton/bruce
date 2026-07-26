import SwiftUI

struct HomeAssistantSetupView: View {
  @ObservedObject var store: HomeAssistantSetupStore
  let mode: BruceMode

  private var copy: HomeAssistantCopy {
    HomeAssistantCopy(mode: mode)
  }

  var body: some View {
    NavigationStack {
      Group {
        switch store.step {
        case .restoring:
          progress(copy.restoringTitle, detail: copy.restoringDetail)
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
        case .authenticationFailed(let candidate, let problem):
          authenticationFailure(candidate, problem: problem)
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
    .onDisappear {
      store.stopDiscovery()
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
          store.requestAuthentication()
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

  private func authenticationFailure(
    _ candidate: HomeAssistantConnectionCandidate,
    problem: HomeAssistantSetupStore.AuthenticationProblem
  ) -> some View {
    scrollableState {
      ContentUnavailableView {
        Label(copy.authenticationTitle(problem), systemImage: "exclamationmark.triangle.fill")
      } description: {
        Text(copy.authenticationMessage(problem))
      } actions: {
        Button("Try Again") {
          store.retryAuthentication()
        }
        .buttonStyle(.borderedProminent)

        Button(copy.recoveryChooseAnotherServer) {
          store.showDiscoveredHomes()
        }
      }
      .padding()
    }
  }

  private func connected(_ credentials: HomeAssistantCredentials) -> some View {
    Form {
      Section {
        Label(
          copy.connectedTitle(instanceName: credentials.instanceName),
          systemImage: "checkmark.circle.fill"
        )
        LabeledContent("Last successful route", value: credentials.lastSuccessfulURL.absoluteString)
      } footer: {
        connectionCheckDescription
      }

      Section {
        connectionManagementLink
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
        LabeledContent(
          "Last successful route",
          value: credentials.lastSuccessfulURL.absoluteString
        )
      } footer: {
        connectionCheckDescription
      }

      Section {
        connectionManagementLink
      }
    }
    .formStyle(.grouped)
  }

  @ViewBuilder
  private var connectionCheckDescription: some View {
    switch store.connectionCheckState {
    case .idle:
      Text(copy.connectionIdle)
    case .checking:
      Text(copy.connectionChecking)
    case .succeeded:
      Text(copy.connectionSucceeded)
    case .failed:
      Text(copy.connectionFailed)
    case .reauthenticationRequired:
      Text(copy.reauthenticationRequired)
    case .disconnectFailed:
      Text(copy.disconnectFailed)
    }
  }

  private func progress(_ title: String, detail: String) -> some View {
    scrollableState {
      VStack(spacing: 16) {
        ProgressView()
          .controlSize(.large)
        Text(title)
          .font(.headline)
        Text(detail)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding()
    }
  }

  @ViewBuilder
  private var connectionManagementLink: some View {
    #if os(macOS)
      SettingsLink {
        Text(copy.manageConnection)
      }
    #else
      NavigationLink(copy.manageConnection) {
        HomeAssistantConnectionManagementView(store: store, copy: copy)
      }
    #endif
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

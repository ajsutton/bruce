import SwiftUI

struct HomeAssistantConnectionSummaryView: View {
  @ObservedObject var store: HomeAssistantSetupStore
  let mode: BruceMode
  let credentials: HomeAssistantCredentials
  @Binding var showsDisconnectConfirmation: Bool
  let reauthenticate: () -> Void

  private var setupCopy: HomeAssistantSetupCopy {
    HomeAssistantSetupCopy(mode: mode)
  }

  private var interfaceCopy: HomeAssistantInterfaceCopy {
    HomeAssistantInterfaceCopy(mode: mode)
  }

  var body: some View {
    Form {
      Section {
        Label(title, systemImage: statusIcon)
        connectionOverviewDetails
      } footer: {
        connectionCheckDescription
      }

      Section {
        connectionManagementControls
      }
    }
    .formStyle(.grouped)
  }

  private var title: String {
    if store.connectionCheckState == .succeeded {
      setupCopy.connectedTitle(instanceName: credentials.instanceName)
    } else {
      setupCopy.configuredTitle(instanceName: credentials.instanceName)
    }
  }

  private var statusIcon: String {
    switch store.connectionCheckState {
    case .checking:
      "ellipsis.circle"
    case .succeeded:
      "checkmark.circle.fill"
    case .failed, .reauthenticationRequired, .disconnectFailed:
      "exclamationmark.circle"
    case .idle:
      "house.circle"
    }
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
  private var connectionOverviewDetails: some View {
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
          reauthenticate: reauthenticate
        )
      }
    #endif
  }
}

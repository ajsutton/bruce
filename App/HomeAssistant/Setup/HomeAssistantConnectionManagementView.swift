#if os(iOS)
  import Accessibility
  import SwiftUI

  struct HomeAssistantConnectionManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: HomeAssistantSetupStore
    let mode: BruceMode
    let reauthenticate: () -> Void
    @State private var showsDisconnectConfirmation = false

    private var setupCopy: HomeAssistantSetupCopy {
      HomeAssistantSetupCopy(mode: mode)
    }

    private var copy: HomeAssistantInterfaceCopy {
      HomeAssistantInterfaceCopy(mode: mode)
    }

    var body: some View {
      Form {
        if let credentials = store.connectedCredentials {
          Section(copy.connectionSection) {
            LabeledContent(copy.homeLabel, value: credentials.instanceName)
            if let internalURL = credentials.internalURL {
              LabeledContent(copy.internalRoute, value: internalURL.absoluteString)
            }
            if let externalURL = credentials.externalURL {
              LabeledContent(copy.externalRoute, value: externalURL.absoluteString)
            }
            LabeledContent(
              copy.lastSuccessfulRoute,
              value: credentials.lastSuccessfulURL.absoluteString
            )
            connectionStatus
          }

          Section {
            Button(setupCopy.testConnection) {
              store.testConnection()
            }
            .disabled(store.connectionCheckState == .checking || store.isDisconnecting)
            .accessibilityValue(
              store.connectionCheckState == .checking ? copy.checking : copy.ready
            )

            if store.connectionCheckState.canSignInAgain {
              Button(copy.signInAgain) {
                reauthenticate()
                dismiss()
              }
              .disabled(store.isDisconnecting)
            }

            Button(setupCopy.changeServer) {
              store.changeServer()
              dismiss()
            }
            .disabled(store.isDisconnecting)

            Button(
              copy.disconnectButtonTitle(state: store.connectionCheckState),
              role: .destructive
            ) {
              showsDisconnectConfirmation = true
            }
            .disabled(store.isDisconnecting)
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle(copy.connectionTitle)
      .navigationBarTitleDisplayMode(.inline)
      .onChange(of: store.connectedCredentials) { _, credentials in
        if credentials == nil {
          dismiss()
        }
      }
      .onChange(of: store.connectionCheckState) { _, state in
        if let announcement = setupCopy.connectionCheckAnnouncement(state) {
          AccessibilityNotification.Announcement(announcement).post()
        }
      }
      .confirmationDialog(
        copy.disconnectQuestion,
        isPresented: $showsDisconnectConfirmation
      ) {
        Button(copy.disconnect, role: .destructive) {
          store.disconnect()
        }
        Button(copy.cancel, role: .cancel) {}
      } message: {
        Text(copy.disconnectExplanation)
      }
    }

    @ViewBuilder
    private var connectionStatus: some View {
      Group {
        if store.isDisconnecting {
          LabeledContent(copy.status) {
            ProgressView()
              .controlSize(.small)
              .accessibilityLabel(copy.disconnectingAccessibility)
          }
        } else {
          switch store.connectionCheckState {
          case .idle:
            LabeledContent(copy.status, value: copy.notChecked)
          case .checking:
            LabeledContent(copy.status) {
              ProgressView()
                .controlSize(.small)
                .accessibilityLabel(copy.checkingConnectionAccessibility)
            }
          case .succeeded:
            LabeledContent(copy.status, value: setupCopy.connectedStatus)
          case .failed(let problem):
            LabeledContent(copy.status, value: setupCopy.connectionFailedStatus(problem))
          case .reauthenticationRequired:
            LabeledContent(copy.status, value: copy.signInRequiredStatus)
          case .disconnectFailed:
            LabeledContent(copy.status, value: setupCopy.disconnectFailed)
          }
        }
      }
    }
  }

#endif

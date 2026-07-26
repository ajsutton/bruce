#if os(iOS)
  import SwiftUI

  struct HomeAssistantConnectionManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: HomeAssistantSetupStore
    let copy: HomeAssistantCopy
    @State private var showsDisconnectConfirmation = false

    var body: some View {
      Form {
        if let credentials = store.connectedCredentials {
          Section("Connection") {
            LabeledContent("Home", value: credentials.instanceName)
            if let internalURL = credentials.internalURL {
              LabeledContent("Internal", value: internalURL.absoluteString)
            }
            if let externalURL = credentials.externalURL {
              LabeledContent("External", value: externalURL.absoluteString)
            }
            LabeledContent(
              "Last successful route",
              value: credentials.lastSuccessfulURL.absoluteString
            )
            connectionStatus
          }

          Section {
            Button(copy.testConnection) {
              store.testConnection()
            }
            .disabled(store.connectionCheckState == .checking || store.isDisconnecting)

            if store.connectionCheckState == .reauthenticationRequired {
              Button("Sign In Again") {
                store.reauthenticate()
                dismiss()
              }
              .disabled(store.isDisconnecting)
            }

            Button(copy.changeServer) {
              store.changeServer()
              dismiss()
            }
            .disabled(store.isDisconnecting)

            Button(disconnectButtonTitle, role: .destructive) {
              showsDisconnectConfirmation = true
            }
            .disabled(store.isDisconnecting)
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Connection")
      .navigationBarTitleDisplayMode(.inline)
      .onChange(of: store.connectedCredentials) { _, credentials in
        if credentials == nil {
          dismiss()
        }
      }
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
    }

    @ViewBuilder
    private var connectionStatus: some View {
      if store.isDisconnecting {
        LabeledContent("Status") {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Disconnecting")
        }
      } else {
        switch store.connectionCheckState {
        case .idle:
          LabeledContent("Status", value: "Not checked")
        case .checking:
          LabeledContent("Status") {
            ProgressView()
              .controlSize(.small)
              .accessibilityLabel("Checking connection")
          }
        case .succeeded:
          LabeledContent("Status", value: copy.connectedStatus)
        case .failed:
          LabeledContent("Status", value: copy.connectionFailedStatus)
        case .reauthenticationRequired:
          LabeledContent("Status", value: "Sign-in required")
        case .disconnectFailed:
          LabeledContent("Status", value: copy.disconnectFailed)
        }
      }
    }

    private var disconnectButtonTitle: String {
      store.connectionCheckState == .disconnectFailed
        ? "Retry Disconnect"
        : "Disconnect from Home Assistant"
    }
  }
#endif

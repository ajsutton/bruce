import SwiftUI

#if os(macOS)
  struct BruceSettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var modeController: BruceModeController
    @ObservedObject var setupStore: HomeAssistantSetupStore
    @State private var showsDisconnectConfirmation = false

    private var copy: HomeAssistantCopy {
      HomeAssistantCopy(mode: modeController.mode)
    }

    private var isFullBruce: Binding<Bool> {
      Binding(
        get: { modeController.mode.isFullBruce },
        set: { isEnabled in
          modeController.requestSelection(isEnabled ? .full : .standard)
        }
      )
    }

    var body: some View {
      Form {
        Section {
          Toggle("Go The Full Bruce", isOn: isFullBruce)
            .disabled(modeController.isTransitioning)
        } footer: {
          Text("Syncs Bruce’s icon, styling and eligible language across your devices.")
        }

        Section("Home Assistant") {
          if case .restoring = setupStore.step {
            LabeledContent("Status") {
              ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Restoring Home Assistant connection")
            }
          } else if let credentials = setupStore.connectedCredentials {
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

            Button(copy.testConnection) {
              setupStore.testConnection()
            }
            .disabled(
              setupStore.connectionCheckState == .checking || setupStore.isDisconnecting
            )

            if setupStore.connectionCheckState == .reauthenticationRequired {
              Button("Sign In Again") {
                setupStore.reauthenticate()
                openWindow(id: "main")
              }
              .disabled(setupStore.isDisconnecting)
            }

            Button(copy.changeServer) {
              setupStore.changeServer()
              openWindow(id: "main")
            }
            .disabled(setupStore.isDisconnecting)

            Button(disconnectButtonTitle, role: .destructive) {
              showsDisconnectConfirmation = true
            }
            .disabled(setupStore.isDisconnecting)
          } else {
            if case .restoreFailed = setupStore.step {
              Text(copy.settingsRestoreFailed)
                .foregroundStyle(.secondary)
            } else {
              Text(copy.notConnected)
                .foregroundStyle(.secondary)
            }

            Button(copy.setUpHomeAssistant) {
              setupStore.changeServer()
              openWindow(id: "main")
            }
          }
        }
      }
      .formStyle(.grouped)
      .frame(width: 440)
      .task {
        await modeController.synchronize()
      }
      .alert(
        "Bruce couldn’t change the app icon",
        isPresented: Binding(
          get: { modeController.appIconErrorMessage != nil },
          set: { isPresented in
            if !isPresented {
              modeController.appIconErrorMessage = nil
            }
          }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(modeController.appIconErrorMessage ?? "")
      }
      .confirmationDialog(
        "Disconnect from Home Assistant?",
        isPresented: $showsDisconnectConfirmation
      ) {
        Button("Disconnect", role: .destructive) {
          setupStore.disconnect()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Bruce will remove the saved Home Assistant connection from this device.")
      }
    }

    @ViewBuilder
    private var connectionStatus: some View {
      if setupStore.isDisconnecting {
        LabeledContent("Status") {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Disconnecting")
        }
      } else {
        switch setupStore.connectionCheckState {
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
      setupStore.connectionCheckState == .disconnectFailed
        ? "Retry Disconnect"
        : "Disconnect from Home Assistant"
    }
  }

  #Preview("Settings") {
    BruceSettingsView(
      modeController: BruceModeController(
        store: PreviewBruceModeStore(),
        iconApplier: PreviewAppIconApplier()
      ),
      setupStore: HomeAssistantSetupStore(discovery: PreviewSettingsDiscovery())
    )
  }

  private struct PreviewSettingsDiscovery: HomeAssistantDiscovering {
    func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
      AsyncThrowingStream { continuation in
        continuation.finish()
      }
    }
  }
#endif

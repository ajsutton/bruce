#if os(macOS)
  struct HomeAssistantMainStatus: Equatable {
    let title: String
    let description: String
    let actionTitle: String

    init(
      step: HomeAssistantSetupStore.Step,
      connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState,
      isDisconnecting: Bool
    ) {
      let presentation =
        if isDisconnecting {
          (
            "Disconnecting from Home Assistant",
            "Bruce is removing the saved connection."
          )
        } else {
          Self.presentation(for: step, connectionCheckState: connectionCheckState)
        }
      title = presentation.0
      description = presentation.1
      actionTitle =
        if case .restoring = step {
          "Open Home Assistant Settings"
        } else if Self.hasConnection(step) {
          "Manage Connection"
        } else {
          "Connect Home Assistant"
        }
    }

    private static func presentation(
      for step: HomeAssistantSetupStore.Step,
      connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState
    ) -> (String, String) {
      switch step {
      case .restoring:
        ("Checking Home Assistant Connection", "Bruce is checking the saved connection.")
      case .restoreFailed:
        (
          "Home Assistant Connection Couldn’t Be Restored",
          "Open Settings to connect Home Assistant again."
        )
      case .configured(let credentials):
        configuredPresentation(credentials, connectionCheckState: connectionCheckState)
      case .connected(let credentials):
        connectedPresentation(credentials, connectionCheckState: connectionCheckState)
      case .readyForAuthentication(let candidate):
        (
          "Waiting for \(candidate.name) Sign-In",
          "Finish signing in with your browser, or manage the connection in Settings."
        )
      case .authenticationFailed(let candidate, _):
        ("Couldn’t Sign In to \(candidate.name)", "Open Settings to try signing in again.")
      case .introduction, .chooseServer, .manualEntry, .confirmation, .unencryptedWarning,
        .onboardingRequired, .cancelled:
        ("Home Assistant Isn’t Connected", "Connect Home Assistant in Bruce Settings.")
      }
    }

    private static func configuredPresentation(
      _ credentials: HomeAssistantCredentials,
      connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState
    ) -> (String, String) {
      switch connectionCheckState {
      case .reauthenticationRequired:
        (
          "Sign In to \(credentials.instanceName) Again",
          "The saved connection needs a new Home Assistant sign-in."
        )
      case .failed(.networkUnavailable):
        (
          "\(credentials.instanceName) Is Unavailable",
          "Bruce couldn’t reach the saved Home Assistant server."
        )
      case .checking:
        (
          "Checking \(credentials.instanceName)",
          "Bruce is checking the saved Home Assistant connection."
        )
      case .disconnectFailed:
        (
          "Couldn’t Disconnect from \(credentials.instanceName)",
          "The saved connection is still present. Open Settings to try again."
        )
      case .idle, .failed, .succeeded:
        (
          "\(credentials.instanceName) Isn’t Connected",
          "Open Settings to check or repair the saved connection."
        )
      }
    }

    private static func connectedPresentation(
      _ credentials: HomeAssistantCredentials,
      connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState
    ) -> (String, String) {
      switch connectionCheckState {
      case .checking:
        (
          "Checking \(credentials.instanceName)",
          "Bruce is checking the Home Assistant connection."
        )
      case .failed, .reauthenticationRequired:
        (
          "\(credentials.instanceName) Isn’t Connected",
          "Open Settings to check or repair the saved connection."
        )
      case .disconnectFailed:
        (
          "Couldn’t Disconnect from \(credentials.instanceName)",
          "The saved connection is still present. Open Settings to try again."
        )
      case .idle, .succeeded:
        (
          "\(credentials.instanceName) Is Connected",
          "Manage the Home Assistant connection in Bruce Settings."
        )
      }
    }

    private static func hasConnection(_ step: HomeAssistantSetupStore.Step) -> Bool {
      switch step {
      case .configured, .connected, .readyForAuthentication, .authenticationFailed:
        true
      case .restoring, .restoreFailed, .introduction, .chooseServer, .manualEntry, .confirmation,
        .unencryptedWarning, .onboardingRequired, .cancelled:
        false
      }
    }
  }
#endif

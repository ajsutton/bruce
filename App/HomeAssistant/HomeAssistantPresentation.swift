struct HomeAssistantPresentation: Equatable {
  enum Screen: Equatable {
    case setup
    case panels
  }

  enum ConnectionProblem: Equatable {
    case removalFailed
    case restoreFailed
    case disconnectFailed
    case signInRequired
    case unavailable
    case needsAttention
  }

  let screen: Screen
  let isConnecting: Bool
  let connectionProblem: ConnectionProblem?
  let access: HomeAssistantAccessState

  var canRefresh: Bool {
    access.isReady
  }

  init(
    step: HomeAssistantSetupStore.Step,
    connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState
  ) {
    screen = Self.screen(for: step)
    isConnecting =
      (step == .restoring && connectionCheckState != .disconnectFailed)
      || step.isFinishingConnection
      || connectionCheckState == .checking
    connectionProblem = Self.connectionProblem(
      for: step,
      connectionCheckState: connectionCheckState
    )
    access = Self.access(for: step, connectionCheckState: connectionCheckState)
  }

  private static func screen(
    for step: HomeAssistantSetupStore.Step
  ) -> Screen {
    switch step {
    case .restoring, .restoreFailed, .configured, .connected, .disconnecting:
      .panels
    case .introduction, .chooseServer, .manualEntry, .confirmation, .unencryptedWarning,
      .onboardingRequired, .readyForAuthentication, .authenticationFailed, .finishingConnection,
      .connectionFailed, .cancelled:
      .setup
    }
  }

  private static func access(
    for step: HomeAssistantSetupStore.Step,
    connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState
  ) -> HomeAssistantAccessState {
    switch step {
    case .connected(let credentials):
      .ready(credentials)
    case .disconnecting, .finishingConnection:
      .loading
    case .restoring:
      .loading
    case .restoreFailed, .configured, .connectionFailed:
      .requiresUserAction
    case .introduction, .chooseServer, .manualEntry, .confirmation, .unencryptedWarning,
      .onboardingRequired, .readyForAuthentication, .authenticationFailed, .cancelled:
      .signedOut
    }
  }

  private static func connectionProblem(
    for step: HomeAssistantSetupStore.Step,
    connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState
  ) -> ConnectionProblem? {
    switch step {
    case .restoring where connectionCheckState == .disconnectFailed:
      .removalFailed
    case .restoreFailed:
      .restoreFailed
    case .configured:
      configuredConnectionProblem(connectionCheckState)
    case .connected:
      connectedConnectionProblem(connectionCheckState)
    case .restoring, .disconnecting, .introduction, .chooseServer, .manualEntry, .confirmation,
      .unencryptedWarning, .onboardingRequired, .readyForAuthentication, .authenticationFailed,
      .finishingConnection, .connectionFailed, .cancelled:
      nil
    }
  }

  private static func connectedConnectionProblem(
    _ connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState
  ) -> ConnectionProblem? {
    switch connectionCheckState {
    case .failed(.networkUnavailable):
      .unavailable
    case .failed:
      .needsAttention
    case .disconnectFailed:
      .disconnectFailed
    case .idle, .checking, .succeeded, .reauthenticationRequired:
      nil
    }
  }

  private static func configuredConnectionProblem(
    _ connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState
  ) -> ConnectionProblem? {
    switch connectionCheckState {
    case .reauthenticationRequired:
      .signInRequired
    case .failed(.networkUnavailable):
      .unavailable
    case .failed, .idle, .succeeded:
      .needsAttention
    case .checking:
      nil
    case .disconnectFailed:
      .disconnectFailed
    }
  }
}

extension HomeAssistantSetupStore.Step {
  fileprivate var isFinishingConnection: Bool {
    if case .finishingConnection = self {
      return true
    }
    return false
  }
}

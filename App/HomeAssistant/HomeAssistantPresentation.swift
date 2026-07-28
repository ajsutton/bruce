import SwiftUI

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
  let connection: HomeAssistantConnectionState

  var canRefresh: Bool {
    if case .connected = connection {
      return true
    }
    return false
  }

  init(
    step: HomeAssistantSetupStore.Step,
    connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState
  ) {
    screen = Self.screen(for: step)
    isConnecting =
      (step == .restoring && connectionCheckState != .disconnectFailed)
      || connectionCheckState == .checking
    connectionProblem = Self.connectionProblem(
      for: step,
      connectionCheckState: connectionCheckState
    )
    connection = Self.connection(for: step)
  }

  func shouldRefresh(when scenePhase: ScenePhase) -> Bool {
    scenePhase == .active && canRefresh
  }

  private static func screen(
    for step: HomeAssistantSetupStore.Step
  ) -> Screen {
    switch step {
    case .restoring, .restoreFailed, .configured, .connected:
      .panels
    case .introduction, .chooseServer, .manualEntry, .confirmation, .unencryptedWarning,
      .onboardingRequired, .readyForAuthentication, .authenticationFailed, .cancelled:
      .setup
    }
  }

  private static func connection(
    for step: HomeAssistantSetupStore.Step
  ) -> HomeAssistantConnectionState {
    switch step {
    case .connected(let credentials):
      .connected(credentials)
    case .restoring:
      .connecting
    case .restoreFailed, .configured:
      .unavailable
    case .introduction, .chooseServer, .manualEntry, .confirmation, .unencryptedWarning,
      .onboardingRequired, .readyForAuthentication, .authenticationFailed, .cancelled:
      .disconnected
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
    case .connected where connectionCheckState == .disconnectFailed:
      .disconnectFailed
    case .restoring, .introduction, .chooseServer, .manualEntry, .confirmation,
      .unencryptedWarning, .onboardingRequired, .readyForAuthentication, .authenticationFailed,
      .connected, .cancelled:
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

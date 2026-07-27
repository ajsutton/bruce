import SwiftUI

struct HomeAssistantTemperaturePresentation: Equatable {
  enum Screen: Equatable {
    case setup
    case temperatures
  }

  let screen: Screen
  let isConnecting: Bool
  let connectionProblem: String?
  let connection: HomeAssistantTemperatureConnection

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
    isConnecting = step == .restoring || connectionCheckState == .checking
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
      .temperatures
    case .introduction, .chooseServer, .manualEntry, .confirmation, .unencryptedWarning,
      .onboardingRequired, .readyForAuthentication, .authenticationFailed, .cancelled:
      .setup
    }
  }

  private static func connection(
    for step: HomeAssistantSetupStore.Step
  ) -> HomeAssistantTemperatureConnection {
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
  ) -> String? {
    switch step {
    case .restoreFailed:
      "The saved Home Assistant connection couldn’t be restored."
    case .configured:
      configuredConnectionProblem(connectionCheckState)
    case .connected where connectionCheckState == .disconnectFailed:
      "Bruce couldn’t disconnect from Home Assistant. The saved connection is still present."
    case .restoring, .introduction, .chooseServer, .manualEntry, .confirmation,
      .unencryptedWarning, .onboardingRequired, .readyForAuthentication, .authenticationFailed,
      .connected, .cancelled:
      nil
    }
  }

  private static func configuredConnectionProblem(
    _ connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState
  ) -> String? {
    switch connectionCheckState {
    case .reauthenticationRequired:
      "Sign in to Home Assistant again to update temperatures."
    case .failed(.networkUnavailable):
      "Home Assistant can’t be reached. Temperatures may be out of date."
    case .failed, .idle, .succeeded:
      "The Home Assistant connection needs attention."
    case .checking:
      nil
    case .disconnectFailed:
      "Bruce couldn’t disconnect from Home Assistant. The saved connection is still present."
    }
  }
}

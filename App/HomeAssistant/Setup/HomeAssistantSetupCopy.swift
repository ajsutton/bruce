import Foundation

struct HomeAssistantSetupCopy {
  let mode: BruceMode

  private var copy: BruceCopy {
    BruceCopy(mode: mode)
  }

  var navigationTitle: String {
    localized("homeAssistantSetup.navigationTitle")
  }

  var introductionTitle: String {
    localized("homeAssistantSetup.introductionTitle")
  }

  var introductionDescription: String {
    localized("homeAssistantSetup.introductionDescription")
  }

  var searching: String {
    localized("homeAssistantSetup.searching")
  }

  var noHomesFound: String {
    localized("homeAssistantSetup.noHomesFound")
  }

  var searchingFooter: String {
    localized("homeAssistantSetup.searchingFooter")
  }

  var searchInactive: String {
    localized("homeAssistantSetup.searchInactive")
  }

  var findHomeAssistant: String {
    localized("homeAssistantSetup.findHomeAssistant")
  }

  var enterAddressManually: String {
    localized("homeAssistantSetup.enterAddressManually")
  }

  var searchAgain: String {
    localized("homeAssistantSetup.searchAgain")
  }

  var chooseAnotherServer: String {
    localized("homeAssistantSetup.chooseAnotherServer")
  }

  var recoveryChooseAnotherServer: String {
    localized("homeAssistantSetup.recoveryChooseAnotherServer")
  }

  var startAgain: String {
    localized("homeAssistantSetup.startAgain")
  }

  var chooseDiscoveredHome: String {
    localized("homeAssistantSetup.chooseDiscoveredHome")
  }

  var manageConnection: String {
    localized("homeAssistantSetup.manageConnection")
  }

  var testConnection: String {
    localized("homeAssistantSetup.testConnection")
  }

  var changeServer: String {
    localized("homeAssistantSetup.changeServer")
  }

  var setUpHomeAssistant: String {
    localized("homeAssistantSetup.setUpHomeAssistant")
  }

  func connectedTitle(instanceName: String) -> String {
    localized("homeAssistantSetup.connectedTitle")
      .replacingOccurrences(of: "%@", with: instanceName)
  }

  var connectionIdle: String {
    localized("homeAssistantSetup.connectionIdle")
  }

  var connectionChecking: String {
    localized("homeAssistantSetup.connectionChecking")
  }

  var connectionSucceeded: String {
    localized("homeAssistantSetup.connectionSucceeded")
  }

  var setupCancelledTitle: String {
    localized("homeAssistantSetup.setupCancelledTitle")
  }

  var notConnected: String {
    localized("homeAssistantSetup.notConnected")
  }

  var connectedStatus: String {
    localized("homeAssistantSetup.connectedStatus")
  }

  func configuredTitle(instanceName: String) -> String {
    localized("homeAssistantSetup.configuredTitle")
      .replacingOccurrences(of: "%@", with: instanceName)
  }

  var restoringTitle: String {
    localized("homeAssistantSetup.restoringTitle")
  }

  var restoringDetail: String {
    localized("homeAssistantSetup.restoringDetail")
  }

  var localNetworkAccessOff: String {
    localized("homeAssistantSetup.localNetworkAccessOff")
  }

  var discoveryFailed: String {
    localized("homeAssistantSetup.discoveryFailed")
  }

  var unencryptedTitle: String {
    localized("homeAssistantSetup.unencryptedTitle")
  }

  var unencryptedMessage: String {
    localized("homeAssistantSetup.unencryptedMessage")
  }

  var onboardingTitle: String {
    localized("homeAssistantSetup.onboardingTitle")
  }

  func onboardingMessage(instanceName: String) -> String {
    localized("homeAssistantSetup.onboardingMessage")
      .replacingOccurrences(of: "%@", with: instanceName)
  }

  var openingHomeAssistant: String {
    localized("homeAssistantSetup.openingHomeAssistant")
  }

  func authenticationHandoff(instanceName: String) -> String {
    localized("homeAssistantSetup.authenticationHandoff")
      .replacingOccurrences(of: "%@", with: instanceName)
  }

  var finishingConnectionTitle: String {
    localized("homeAssistantSetup.finishingConnectionTitle")
  }

  func finishingConnectionDetail(instanceName: String) -> String {
    localized("homeAssistantSetup.finishingConnectionDetail")
      .replacingOccurrences(of: "%@", with: instanceName)
  }

  var postAuthenticationFailureTitle: String {
    localized("homeAssistantSetup.postAuthenticationFailureTitle")
  }

  func postAuthenticationFailureDetail(
    _ problem: HomeAssistantSetupStore.ConnectionCheckProblem
  ) -> String {
    switch problem {
    case .networkUnavailable:
      localized("homeAssistantSetup.postAuthenticationFailure.networkUnavailable")
    case .serverRejectedRequest:
      localized("homeAssistantSetup.postAuthenticationFailure.serverRejectedRequest")
    case .incompatibleServer:
      localized("homeAssistantSetup.postAuthenticationFailure.incompatibleServer")
    case .invalidResponse:
      localized("homeAssistantSetup.postAuthenticationFailure.invalidResponse")
    case .other:
      localized("homeAssistantSetup.postAuthenticationFailure.other")
    }
  }

  func connectionFailed(_ problem: HomeAssistantSetupStore.ConnectionCheckProblem) -> String {
    switch problem {
    case .networkUnavailable:
      localized("homeAssistantSetup.connectionFailed.networkUnavailable")
    case .serverRejectedRequest:
      localized("homeAssistantSetup.connectionFailed.serverRejectedRequest")
    case .incompatibleServer:
      localized("homeAssistantSetup.connectionFailed.incompatibleServer")
    case .invalidResponse:
      localized("homeAssistantSetup.connectionFailed.invalidResponse")
    case .other:
      localized("homeAssistantSetup.connectionFailed.other")
    }
  }

  func connectionFailedStatus(
    _ problem: HomeAssistantSetupStore.ConnectionCheckProblem
  ) -> String {
    switch problem {
    case .networkUnavailable:
      localized("homeAssistantSetup.connectionFailedStatus.networkUnavailable")
    case .serverRejectedRequest:
      localized("homeAssistantSetup.connectionFailedStatus.serverRejectedRequest")
    case .incompatibleServer:
      localized("homeAssistantSetup.connectionFailedStatus.incompatibleServer")
    case .invalidResponse:
      localized("homeAssistantSetup.connectionFailedStatus.invalidResponse")
    case .other:
      localized("homeAssistantSetup.connectionFailedStatus.other")
    }
  }

  var reauthenticationRequired: String {
    localized("homeAssistantSetup.reauthenticationRequired")
  }

  var disconnectFailed: String {
    localized("homeAssistantSetup.disconnectFailed")
  }

  var restoreFailedTitle: String {
    localized("homeAssistantSetup.restoreFailedTitle")
  }

  var restoreFailedMessage: String {
    localized("homeAssistantSetup.restoreFailedMessage")
  }

  var settingsRestoreFailed: String {
    localized("homeAssistantSetup.settingsRestoreFailed")
  }

  private func localized(_ key: String.LocalizationValue) -> String {
    copy.text(.localized(key))
  }

}

extension HomeAssistantSetupCopy {
  func connectionCheckAnnouncement(
    _ state: HomeAssistantSetupStore.ConnectionCheckState
  ) -> String? {
    switch state {
    case .idle:
      nil
    case .checking:
      connectionChecking
    case .succeeded:
      connectionSucceeded
    case .failed(let problem):
      connectionFailed(problem)
    case .reauthenticationRequired:
      reauthenticationRequired
    case .disconnectFailed:
      disconnectFailed
    }
  }
}

import Foundation

struct HomeAssistantInterfaceCopy {
  let mode: BruceMode

  var homeSection: String { localized("homeAssistantInterface.homeSection") }
  var nameLabel: String { localized("homeAssistantInterface.nameLabel") }
  var addressLabel: String { localized("homeAssistantInterface.addressLabel") }
  var signIn: String {
    localized("homeAssistantInterface.signIn")
  }
  var continueButton: String {
    localized("homeAssistantInterface.continueButton")
  }
  var cancel: String { localized("homeAssistantInterface.cancel") }
  var done: String { localized("homeAssistantInterface.done") }
  var retryAuthentication: String {
    localized("homeAssistantInterface.retryAuthentication")
  }
  var retryDiscovery: String {
    localized("homeAssistantInterface.retryDiscovery")
  }
  var openSettings: String { localized("homeAssistantInterface.openSettings") }
  var homesSection: String { localized("homeAssistantInterface.homesSection") }
  var selected: String { localized("homeAssistantInterface.selected") }
  var resolvingAddress: String {
    localized("homeAssistantInterface.resolvingAddress")
  }
  var remoteAccessRequiresHTTPS: String {
    localized("homeAssistantInterface.remoteAccessRequiresHTTPS")
  }
  var allowLocalNetworkIOS: String {
    localized("homeAssistantInterface.allowLocalNetworkIOS")
  }
  var allowLocalNetworkMac: String {
    localized("homeAssistantInterface.allowLocalNetworkMac")
  }
  var addressField: String {
    localized("homeAssistantInterface.addressField")
  }
  var addressHelp: String {
    localized("homeAssistantInterface.addressHelp")
  }
  var addressErrorPrefix: String { localized("homeAssistantInterface.addressErrorPrefix") }
  var technicalDetails: String {
    localized("homeAssistantInterface.technicalDetails")
  }
  var disconnectQuestion: String {
    localized("homeAssistantInterface.disconnectQuestion")
  }
  var removeConnectionQuestion: String {
    localized("homeAssistantInterface.removeConnectionQuestion")
  }
  var disconnect: String {
    localized("homeAssistantInterface.disconnect")
  }
  var removeConnection: String {
    localized("homeAssistantInterface.removeConnection")
  }
  var retryDisconnect: String {
    localized("homeAssistantInterface.retryDisconnect")
  }
  var disconnectExplanation: String {
    localized("homeAssistantInterface.disconnectExplanation")
  }
  var disconnecting: String {
    localized("homeAssistantInterface.disconnecting")
  }
  var disconnectingAccessibility: String {
    localized("homeAssistantInterface.disconnectingAccessibility")
  }
  var couldNotRemoveConnection: String {
    localized("homeAssistantInterface.couldNotRemoveConnection")
  }
  var couldNotRemoveConnectionMessage: String {
    localized("homeAssistantInterface.couldNotRemoveConnectionMessage")
  }
  var tryRemovingAgain: String {
    localized("homeAssistantInterface.tryRemovingAgain")
  }
  var setUpAgain: String {
    localized("homeAssistantInterface.setUpAgain")
  }
  var connectionSection: String { localized("homeAssistantInterface.connectionSection") }
  var connectionTitle: String { localized("homeAssistantInterface.connectionTitle") }
  var homeLabel: String { localized("homeAssistantInterface.homeLabel") }
  var internalRoute: String { localized("homeAssistantInterface.internalRoute") }
  var externalRoute: String { localized("homeAssistantInterface.externalRoute") }
  var lastSuccessfulRoute: String {
    localized("homeAssistantInterface.lastSuccessfulRoute")
  }
  var status: String { localized("homeAssistantInterface.status") }
  var notChecked: String { localized("homeAssistantInterface.notChecked") }
  var checking: String { localized("homeAssistantInterface.checking") }
  var ready: String { localized("homeAssistantInterface.ready") }
  var checkingConnectionAccessibility: String {
    localized("homeAssistantInterface.checkingConnectionAccessibility")
  }
  var signInRequiredStatus: String {
    localized("homeAssistantInterface.signInRequiredStatus")
  }
  var signInAgain: String {
    localized("homeAssistantInterface.signInAgain")
  }
  var continueWithHTTP: String {
    localized("homeAssistantInterface.continueWithHTTP")
  }
  var goBackFromHTTP: String {
    localized("homeAssistantInterface.goBackFromHTTP")
  }

  func disconnectButtonTitle(
    state: HomeAssistantSetupStore.ConnectionCheckState
  ) -> String {
    state == .disconnectFailed ? retryDisconnect : disconnect
  }

  func presentationProblem(
    _ problem: HomeAssistantPresentation.ConnectionProblem
  ) -> String {
    switch problem {
    case .removalFailed:
      couldNotRemoveConnectionMessage
    case .restoreFailed:
      localized("homeAssistantInterface.presentationProblem.restoreFailed")
    case .disconnectFailed:
      localized("homeAssistantInterface.presentationProblem.disconnectFailed")
    case .signInRequired:
      localized("homeAssistantInterface.presentationProblem.signInRequired")
    case .unavailable:
      localized("homeAssistantInterface.presentationProblem.unavailable")
    case .needsAttention:
      localized("homeAssistantInterface.presentationProblem.needsAttention")
    }
  }

  private func localized(_ key: String.LocalizationValue) -> String {
    BruceCopy(mode: mode).text(.localized(key))
  }

}

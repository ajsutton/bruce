import Foundation

struct HomeAssistantAuthenticationCopy {
  let mode: BruceMode

  func authenticationTitle(
    _ problem: HomeAssistantSetupStore.AuthenticationProblem
  ) -> String {
    switch problem {
    case .rejected:
      localized("homeAssistantAuthentication.authenticationTitle.rejected")
    case .inactiveUser:
      localized("homeAssistantAuthentication.authenticationTitle.inactiveUser")
    case .browserUnavailable:
      localized("homeAssistantAuthentication.authenticationTitle.browserUnavailable")
    case .browserSessionEnded:
      localized("homeAssistantAuthentication.authenticationTitle.browserSessionEnded")
    case .unavailable:
      localized("homeAssistantAuthentication.authenticationTitle.unavailable")
    case .invalidCallback:
      localized("homeAssistantAuthentication.authenticationTitle.invalidCallback")
    case .verificationFailed:
      localized("homeAssistantAuthentication.authenticationTitle.verificationFailed")
    case .couldNotSave:
      localized("homeAssistantAuthentication.authenticationTitle.couldNotSave")
    case .other:
      localized("homeAssistantAuthentication.authenticationTitle.other")
    }
  }

  func authenticationMessage(
    _ problem: HomeAssistantSetupStore.AuthenticationProblem
  ) -> String {
    switch problem {
    case .rejected:
      localized("homeAssistantAuthentication.authenticationMessage.rejected")
    case .inactiveUser:
      localized("homeAssistantAuthentication.authenticationMessage.inactiveUser")
    case .browserUnavailable:
      localized("homeAssistantAuthentication.authenticationMessage.browserUnavailable")
    case .browserSessionEnded:
      localized("homeAssistantAuthentication.authenticationMessage.browserSessionEnded")
    case .unavailable:
      localized("homeAssistantAuthentication.authenticationMessage.unavailable")
    case .invalidCallback:
      localized("homeAssistantAuthentication.authenticationMessage.invalidCallback")
    case .verificationFailed:
      localized("homeAssistantAuthentication.authenticationMessage.verificationFailed")
    case .couldNotSave:
      localized("homeAssistantAuthentication.authenticationMessage.couldNotSave")
    case .other:
      localized("homeAssistantAuthentication.authenticationMessage.other")
    }
  }

  func manualValidationMessage(
    _ error: HomeAssistantServerAddress.ValidationError
  ) -> String {
    switch error {
    case .empty:
      localized("homeAssistantAuthentication.manualValidationMessage.empty")
    case .unsupportedScheme:
      localized("homeAssistantAuthentication.manualValidationMessage.unsupportedScheme")
    case .missingHost:
      localized("homeAssistantAuthentication.manualValidationMessage.missingHost")
    case .containsCredentials:
      localized("homeAssistantAuthentication.manualValidationMessage.containsCredentials")
    case .containsQuery:
      localized("homeAssistantAuthentication.manualValidationMessage.containsQuery")
    case .containsFragment:
      localized("homeAssistantAuthentication.manualValidationMessage.containsFragment")
    case .pointsToEndpoint:
      localized("homeAssistantAuthentication.manualValidationMessage.pointsToEndpoint")
    }
  }

  private func localized(_ key: String.LocalizationValue) -> String {
    BruceCopy(mode: mode).text(.localized(key))
  }
}

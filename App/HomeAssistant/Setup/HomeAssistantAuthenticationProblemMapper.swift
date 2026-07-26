import Foundation

enum HomeAssistantAuthenticationProblemMapper {
  static func problem(
    for error: any Error
  ) -> HomeAssistantSetupStore.AuthenticationProblem {
    if let authenticationError = error as? HomeAssistantAuthenticationError {
      return problem(for: authenticationError)
    }
    if error is HomeAssistantCredentialStoreError {
      return .couldNotSave
    }
    if let apiError = error as? HomeAssistantAPIError {
      return problem(for: apiError)
    }
    if error is URLError {
      return .unavailable
    }
    return .other
  }

  private static func problem(
    for error: HomeAssistantAuthenticationError
  ) -> HomeAssistantSetupStore.AuthenticationProblem {
    switch error {
    case .authorizationRejected:
      return .rejected
    case .serverRejectedRequest(let statusCode, let description):
      if statusCode >= 500 {
        return .unavailable
      }
      if description?.localizedCaseInsensitiveContains("inactive") == true {
        return .inactiveUser
      }
      return .rejected
    case .invalidCallback, .stateMismatch, .missingAuthorizationCode:
      return .invalidCallback
    case .invalidInstanceURL, .invalidTokenResponse, .unexpectedResponse,
      .randomGenerationFailed, .presentationUnavailable:
      return .other
    }
  }

  private static func problem(
    for error: HomeAssistantAPIError
  ) -> HomeAssistantSetupStore.AuthenticationProblem {
    switch error {
    case .incompatibleServer, .invalidResponse, .server, .unauthorized:
      .verificationFailed
    case .noCredentials, .invalidServerURL, .reauthenticationRequired, .staleOperation:
      .other
    }
  }
}

import Foundation

enum HomeAssistantAuthenticationError: Error, Equatable {
  case invalidInstanceURL
  case invalidCallback
  case stateMismatch
  case authorizationRejected(String?)
  case missingAuthorizationCode
  case invalidTokenResponse
  case serverRejectedRequest(statusCode: Int, description: String?)
  case unexpectedResponse
  case randomGenerationFailed
  case presentationUnavailable
}

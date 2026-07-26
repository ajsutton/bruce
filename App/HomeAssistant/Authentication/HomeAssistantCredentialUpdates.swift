import Foundation

enum HomeAssistantCredentialUpdates {
  static func refreshed(
    _ credentials: HomeAssistantCredentials,
    _ token: HomeAssistantToken,
    _ successfulURL: URL
  ) -> HomeAssistantCredentials {
    var updated = credentials
    updated.accessToken = token.accessToken
    updated.refreshToken = token.refreshToken ?? credentials.refreshToken
    updated.accessTokenExpiresAt = token.expiresAt
    updated.lastSuccessfulURL = successfulURL
    return updated
  }

  static func recording(
    _ successfulURL: URL,
    in credentials: HomeAssistantCredentials
  ) -> HomeAssistantCredentials {
    var updated = credentials
    updated.lastSuccessfulURL = successfulURL
    return updated
  }
}

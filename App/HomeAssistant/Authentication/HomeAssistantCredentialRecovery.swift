import Foundation

enum HomeAssistantCredentialRecovery {
  static func repair(
    _ credentials: HomeAssistantCredentials?,
    replacing persistedCredentials: HomeAssistantCredentials?,
    in store: any HomeAssistantCredentialStoring
  ) async throws -> Bool {
    try await store.replace(credentials, ifCurrentIs: persistedCredentials)
  }
}

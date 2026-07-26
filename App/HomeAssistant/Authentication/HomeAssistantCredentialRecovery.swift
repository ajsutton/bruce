import Foundation

enum HomeAssistantCredentialRecovery {
  static func repair(
    _ credentials: HomeAssistantCredentials?,
    in store: any HomeAssistantCredentialStoring
  ) async throws {
    if let credentials {
      try await store.save(credentials)
    } else {
      try await store.delete()
    }
  }

  static func checkCancellation(
    credentials: HomeAssistantCredentials?,
    store: any HomeAssistantCredentialStoring
  ) async throws {
    guard Task.isCancelled else {
      return
    }
    try await repair(credentials, in: store)
    throw CancellationError()
  }
}

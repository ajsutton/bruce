protocol HomeAssistantCredentialStoring: Sendable {
  func load() async throws -> HomeAssistantCredentials?
  func save(_ credentials: HomeAssistantCredentials) async throws
  func replace(
    _ credentials: HomeAssistantCredentials?,
    ifCurrentIs original: HomeAssistantCredentials?
  ) async throws -> Bool
  func delete() async throws
}

enum HomeAssistantCredentialStoreError: Error, Equatable {
  case corruptData
  case keychainFailure(Int32)
}

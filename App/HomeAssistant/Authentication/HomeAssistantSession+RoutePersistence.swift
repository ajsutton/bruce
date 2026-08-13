import Foundation

extension HomeAssistantSession {
  func rememberSuccessful(
    _ baseURL: URL,
    original: HomeAssistantCredentials,
    generation: Int,
    authenticationSessionEpoch: Int,
    authenticationOperationEpoch: Int
  ) async throws {
    let updated = HomeAssistantCredentialUpdates.recording(baseURL, in: original)
    guard self.authenticationOperationEpoch == authenticationOperationEpoch else {
      throw HomeAssistantAPIError.staleOperation
    }
    guard
      original.lastSuccessfulURL != baseURL,
      credentials?.lastSuccessfulURL != baseURL
    else { return }
    if credentials == updated, successfulRouteSourceGeneration == generation { return }
    guard credentialGeneration == generation, credentials == original else { return }

    try await persistSuccessfulRoute(
      updated,
      original: original,
      generation: generation,
      authenticationSessionEpoch: authenticationSessionEpoch,
      authenticationOperationEpoch: authenticationOperationEpoch
    )
  }

  private func persistSuccessfulRoute(
    _ updated: HomeAssistantCredentials,
    original: HomeAssistantCredentials,
    generation: Int,
    authenticationSessionEpoch: Int,
    authenticationOperationEpoch: Int
  ) async throws {
    try await withHomeAssistantPersistence(gate: persistenceGate) {
      guard
        self.authenticationSessionEpoch == authenticationSessionEpoch,
        self.authenticationOperationEpoch == authenticationOperationEpoch
      else { throw HomeAssistantAPIError.staleOperation }
      if credentials == updated, successfulRouteSourceGeneration == generation { return }
      guard credentialGeneration == generation, credentials == original else { return }
      guard try await credentialStore.replace(updated, ifCurrentIs: original) else {
        try await reconcilePersistedCredentials(ifCurrentIs: original, generation: generation)
        throw HomeAssistantAPIError.staleOperation
      }
      try await checkPersistenceCancellation(
        restoring: original,
        replacing: updated,
        generation: generation
      )
      guard
        self.authenticationSessionEpoch == authenticationSessionEpoch,
        self.authenticationOperationEpoch == authenticationOperationEpoch,
        credentialGeneration == generation,
        credentials == original
      else {
        _ = try await HomeAssistantCredentialRecovery.repair(
          credentials,
          replacing: updated,
          in: credentialStore
        )
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = updated
      successfulRouteSourceGeneration = generation
      credentialGeneration += 1
    }
  }
}

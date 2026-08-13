import Foundation

actor HomeAssistantSession {
  let credentialStore: any HomeAssistantCredentialStoring
  let transport: HomeAssistantAuthenticatedTransport
  let tokenRefresher: HomeAssistantTokenRefresher
  private let now: @Sendable () -> Date
  private let refreshLeeway: TimeInterval
  let persistenceGate: HomeAssistantPersistenceGate
  private let credentialEvents: HomeAssistantCredentialEvents?

  var credentials: HomeAssistantCredentials?
  var credentialGeneration = 0, authenticationSessionEpoch = 0
  var rejectedCredentialGeneration: Int?, successfulRouteSourceGeneration: Int?
  var isDisconnecting = false

  init(
    credentialStore: any HomeAssistantCredentialStoring,
    authenticationClient: HomeAssistantAuthenticationClient,
    loader: any HomeAssistantHTTPDataLoading,
    now: @escaping @Sendable () -> Date = Date.init,
    refreshLeeway: TimeInterval = 60,
    persistenceGate: HomeAssistantPersistenceGate = HomeAssistantPersistenceGate(),
    credentialEvents: HomeAssistantCredentialEvents? = nil
  ) {
    self.credentialStore = credentialStore
    transport = HomeAssistantAuthenticatedTransport(loader: loader)
    tokenRefresher = HomeAssistantTokenRefresher(authenticationClient: authenticationClient)
    self.now = now
    self.refreshLeeway = refreshLeeway
    self.persistenceGate = persistenceGate
    self.credentialEvents = credentialEvents
  }

  func restore() async throws -> Bool {
    let generation = reserveCredentialGeneration()
    await tokenRefresher.cancel()
    return try await withHomeAssistantPersistence(gate: persistenceGate) {
      let restoredCredentials = try await credentialStore.load()
      try Task.checkCancellation()
      guard credentialGeneration == generation else {
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = restoredCredentials
      commitAuthenticationReplacement()
      await publishCredentialSnapshot()
      return credentials != nil
    }
  }

  func install(_ newCredentials: HomeAssistantCredentials) async throws {
    let generation = reserveCredentialGeneration()
    let previousCredentials = credentials
    await tokenRefresher.cancel()
    try await withHomeAssistantPersistence(gate: persistenceGate) {
      try await credentialStore.save(newCredentials)
      try await checkPersistenceCancellation(
        restoring: previousCredentials,
        replacing: newCredentials,
        generation: generation
      )
      guard credentialGeneration == generation else {
        _ = try await HomeAssistantCredentialRecovery.repair(
          credentials,
          replacing: newCredentials,
          in: credentialStore
        )
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = newCredentials
      commitAuthenticationReplacement()
      await publishCredentialSnapshot()
    }
  }

  func verifyAndInstall(
    _ newCredentials: HomeAssistantCredentials,
    validate: @escaping @Sendable (Data) throws -> Void
  ) async throws {
    let generation = reserveCredentialGeneration()
    let previousCredentials = credentials
    await tokenRefresher.cancel()
    let response = try await transport.getFirstAvailable(
      path: "api/",
      credentials: newCredentials,
      validate: validate
    )
    try Task.checkCancellation()
    var verifiedCredentials = newCredentials
    verifiedCredentials.lastSuccessfulURL = response.baseURL
    try await withHomeAssistantPersistence(gate: persistenceGate) {
      try await credentialStore.save(verifiedCredentials)
      try await checkPersistenceCancellation(
        restoring: previousCredentials,
        replacing: verifiedCredentials,
        generation: generation
      )
      guard credentialGeneration == generation else {
        _ = try await HomeAssistantCredentialRecovery.repair(
          credentials,
          replacing: verifiedCredentials,
          in: credentialStore
        )
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = verifiedCredentials
      commitAuthenticationReplacement()
      await publishCredentialSnapshot()
    }
  }

  func refreshIfNeeded(force: Bool) async throws {
    guard !isDisconnecting else { throw HomeAssistantAPIError.noCredentials }
    guard let credentials else {
      if rejectedCredentialGeneration != nil {
        throw HomeAssistantAPIError.reauthenticationRequired
      }
      throw HomeAssistantAPIError.noCredentials
    }
    if !force, credentials.accessTokenExpiresAt > now().addingTimeInterval(refreshLeeway) {
      return
    }
    let generation = credentialGeneration
    let tokenResult: (HomeAssistantToken, URL)
    do {
      tokenResult = try await tokenRefresher.token(for: credentials)
    } catch {
      if HomeAssistantRequestRouter.isRejectedRefresh(error) {
        try await rejectCredentials(generation: generation)
      }
      throw error
    }
    try await installRefreshedToken(
      tokenResult.0,
      successfulURL: tokenResult.1,
      original: credentials,
      generation: generation
    )
  }

}

extension HomeAssistantSession {
  func credentialSnapshot() -> HomeAssistantCredentialSnapshot {
    let availability: HomeAssistantCredentialSnapshot.Availability
    if credentials != nil {
      availability = .ready
    } else if rejectedCredentialGeneration != nil {
      availability = .rejected
    } else {
      availability = .missing
    }
    return HomeAssistantCredentialSnapshot(
      authenticationSessionEpoch: authenticationSessionEpoch,
      persistenceGeneration: credentialGeneration,
      availability: availability
    )
  }

  func publishCredentialSnapshot() async {
    guard let credentialEvents else { return }
    await credentialEvents.publish(credentialSnapshot())
  }
}

extension HomeAssistantSession {
  func loadResponse(
    path: String,
    queryItems: [URLQueryItem],
    body: Data?,
    credentials: HomeAssistantCredentials,
    routeSelection: RouteSelection
  ) async throws -> HomeAssistantAuthenticatedResponse {
    if case .firstValid(let validate) = routeSelection {
      return try await transport.getFirstAvailable(
        path: path,
        credentials: credentials,
        validate: validate
      )
    }
    if let body {
      return try await transport.post(
        path: path,
        body: body,
        credentials: credentials
      )
    }
    return try await transport.get(
      path: path,
      queryItems: queryItems,
      credentials: credentials
    )
  }

  private func installRefreshedToken(
    _ token: HomeAssistantToken,
    successfulURL: URL,
    original: HomeAssistantCredentials,
    generation: Int
  ) async throws {
    let refreshed = HomeAssistantCredentialUpdates.refreshed(original, token, successfulURL)
    if credentials == refreshed {
      return
    }
    guard credentialGeneration == generation, credentials == original else {
      throw HomeAssistantAPIError.staleOperation
    }
    try await withHomeAssistantPersistence(gate: persistenceGate) {
      if credentials == refreshed {
        return
      }
      guard credentialGeneration == generation, credentials == original else {
        throw HomeAssistantAPIError.staleOperation
      }
      guard try await credentialStore.replace(refreshed, ifCurrentIs: original) else {
        try await reconcilePersistedCredentials(
          ifCurrentIs: original,
          generation: generation
        )
        throw HomeAssistantAPIError.staleOperation
      }
      try await checkPersistenceCancellation(
        restoring: original,
        replacing: refreshed,
        generation: generation
      )
      guard credentialGeneration == generation, credentials == original else {
        _ = try await HomeAssistantCredentialRecovery.repair(
          credentials,
          replacing: refreshed,
          in: credentialStore
        )
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = refreshed
      successfulRouteSourceGeneration = nil
      credentialGeneration += 1
      await publishCredentialSnapshot()
    }
  }

  func rejectCredentials(generation: Int) async throws -> Never {
    if credentials == nil, rejectedCredentialGeneration == generation {
      throw HomeAssistantAPIError.reauthenticationRequired
    }
    guard credentialGeneration == generation, let rejectedCredentials = credentials else {
      throw HomeAssistantAPIError.staleOperation
    }
    try await withHomeAssistantPersistence(gate: persistenceGate) {
      if credentials == nil, rejectedCredentialGeneration == generation {
        throw HomeAssistantAPIError.reauthenticationRequired
      }
      guard
        try await credentialStore.replace(nil, ifCurrentIs: rejectedCredentials)
      else {
        try await reconcilePersistedCredentials(
          ifCurrentIs: rejectedCredentials,
          generation: generation
        )
        throw HomeAssistantAPIError.staleOperation
      }
      try await checkPersistenceCancellation(
        restoring: rejectedCredentials,
        replacing: nil,
        generation: generation
      )
      guard credentialGeneration == generation, credentials == rejectedCredentials else {
        _ = try await HomeAssistantCredentialRecovery.repair(
          credentials,
          replacing: nil,
          in: credentialStore
        )
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = nil
      credentialGeneration += 1
      authenticationSessionEpoch += 1
      rejectedCredentialGeneration = generation
      successfulRouteSourceGeneration = nil
      await publishCredentialSnapshot()
    }
    throw HomeAssistantAPIError.reauthenticationRequired
  }

  func rememberSuccessful(
    _ baseURL: URL,
    original: HomeAssistantCredentials,
    generation: Int
  ) async throws {
    let updated = HomeAssistantCredentialUpdates.recording(baseURL, in: original)
    if credentials == updated, successfulRouteSourceGeneration == generation {
      return
    }
    guard credentialGeneration == generation, credentials == original else {
      throw HomeAssistantAPIError.staleOperation
    }
    guard original.lastSuccessfulURL != baseURL else {
      return
    }
    try await withHomeAssistantPersistence(gate: persistenceGate) {
      if credentials == updated, successfulRouteSourceGeneration == generation {
        return
      }
      guard credentialGeneration == generation, credentials == original else {
        throw HomeAssistantAPIError.staleOperation
      }
      guard try await credentialStore.replace(updated, ifCurrentIs: original) else {
        try await reconcilePersistedCredentials(
          ifCurrentIs: original,
          generation: generation
        )
        throw HomeAssistantAPIError.staleOperation
      }
      try await checkPersistenceCancellation(
        restoring: original,
        replacing: updated,
        generation: generation
      )
      guard credentialGeneration == generation, credentials == original else {
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

  func reserveCredentialGeneration() -> Int {
    credentialGeneration += 1
    return credentialGeneration
  }

  private func commitAuthenticationReplacement() {
    authenticationSessionEpoch += 1
    rejectedCredentialGeneration = nil
    successfulRouteSourceGeneration = nil
  }

  private func reconcilePersistedCredentials(
    ifCurrentIs expectedCredentials: HomeAssistantCredentials?,
    generation: Int
  ) async throws {
    let persistedCredentials = try await credentialStore.load()
    guard credentialGeneration == generation, credentials == expectedCredentials else {
      return
    }
    credentials = persistedCredentials
    credentialGeneration += 1
    authenticationSessionEpoch += 1
    rejectedCredentialGeneration = nil
    successfulRouteSourceGeneration = nil
    await publishCredentialSnapshot()
  }

  private func checkPersistenceCancellation(
    restoring previousCredentials: HomeAssistantCredentials?,
    replacing persistedCredentials: HomeAssistantCredentials?,
    generation: Int
  ) async throws {
    guard Task.isCancelled else { return }
    let didRestore = try await HomeAssistantCredentialRecovery.repair(
      previousCredentials,
      replacing: persistedCredentials,
      in: credentialStore
    )
    if !didRestore {
      try await reconcilePersistedCredentials(
        ifCurrentIs: previousCredentials,
        generation: generation
      )
    }
    throw CancellationError()
  }
}

import Foundation

actor HomeAssistantSession {
  typealias CredentialRejectionWaiter = CheckedContinuation<Void, any Error>

  struct CredentialRejectionAttempt {
    let id: UUID
    let generation: Int
    let operationEpoch: Int
    var task: Task<Void, Never>?
    var waiters: [UUID: CredentialRejectionWaiter]
  }

  let credentialStore: any HomeAssistantCredentialStoring
  let transport: HomeAssistantAuthenticatedTransport
  let tokenRefresher: HomeAssistantTokenRefresher
  private let now: @Sendable () -> Date
  private let refreshLeeway: TimeInterval
  let persistenceGate: HomeAssistantPersistenceGate
  private let credentialEvents: HomeAssistantCredentialEvents?
  let rejectionWaiterRegistered: @Sendable (Int) -> Void

  var credentials: HomeAssistantCredentials?
  var credentialGeneration = 0, authenticationSessionEpoch = 0
  var authenticationOperationEpoch = 0
  var pendingReplacementOperationEpoch: Int?
  var credentialRejectionAttempt: CredentialRejectionAttempt?
  var rejectedCredentialGeneration: Int?, successfulRouteSourceGeneration: Int?
  var isDisconnecting = false

  init(
    credentialStore: any HomeAssistantCredentialStoring,
    authenticationClient: HomeAssistantAuthenticationClient,
    loader: any HomeAssistantHTTPDataLoading,
    now: @escaping @Sendable () -> Date = Date.init,
    refreshLeeway: TimeInterval = 60,
    persistenceGate: HomeAssistantPersistenceGate = HomeAssistantPersistenceGate(),
    credentialEvents: HomeAssistantCredentialEvents? = nil,
    refreshWaiterRegistered: @escaping @Sendable (Int) -> Void = { _ in },
    rejectionWaiterRegistered: @escaping @Sendable (Int) -> Void = { _ in }
  ) {
    self.credentialStore = credentialStore
    transport = HomeAssistantAuthenticatedTransport(loader: loader)
    tokenRefresher = HomeAssistantTokenRefresher(
      authenticationClient: authenticationClient,
      waiterRegistered: refreshWaiterRegistered
    )
    self.now = now
    self.refreshLeeway = refreshLeeway
    self.persistenceGate = persistenceGate
    self.credentialEvents = credentialEvents
    self.rejectionWaiterRegistered = rejectionWaiterRegistered
  }

  func restore() async throws -> Bool {
    try await settleCredentialRejectionBeforeReplacement()
    guard rejectedCredentialGeneration == nil else {
      throw HomeAssistantAPIError.reauthenticationRequired
    }
    let generation = reserveCredentialGeneration()
    let operationEpoch = authenticationOperationEpoch
    defer { finishAuthenticationReplacement(operationEpoch: operationEpoch) }
    await tokenRefresher.cancel()
    return try await withHomeAssistantPersistence(gate: persistenceGate) {
      let restoredCredentials = try await credentialStore.load()
      try Task.checkCancellation()
      guard credentialGeneration == generation else {
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = restoredCredentials
      commitAuthenticationReplacement()
      finishAuthenticationReplacement(operationEpoch: operationEpoch)
      await publishCredentialSnapshot()
      return credentials != nil
    }
  }

  func install(_ newCredentials: HomeAssistantCredentials) async throws {
    try await settleCredentialRejectionBeforeReplacement()
    let generation = reserveCredentialGeneration()
    let operationEpoch = authenticationOperationEpoch
    defer { finishAuthenticationReplacement(operationEpoch: operationEpoch) }
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
      finishAuthenticationReplacement(operationEpoch: operationEpoch)
      await publishCredentialSnapshot()
    }
  }

  func verifyAndInstall(
    _ newCredentials: HomeAssistantCredentials,
    validate: @escaping @Sendable (Data) throws -> Void
  ) async throws {
    try await settleCredentialRejectionBeforeReplacement()
    let generation = reserveCredentialGeneration()
    let operationEpoch = authenticationOperationEpoch
    defer { finishAuthenticationReplacement(operationEpoch: operationEpoch) }
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
      finishAuthenticationReplacement(operationEpoch: operationEpoch)
      await publishCredentialSnapshot()
    }
  }

  func refreshIfNeeded(force: Bool) async throws {
    guard !isDisconnecting else { throw HomeAssistantAPIError.noCredentials }
    if rejectedCredentialGeneration != nil {
      throw HomeAssistantAPIError.reauthenticationRequired
    }
    guard pendingReplacementOperationEpoch == nil else {
      throw HomeAssistantAPIError.staleOperation
    }
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
    let operationEpoch = authenticationOperationEpoch
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
      generation: generation,
      authenticationOperationEpoch: operationEpoch
    )
  }

}

extension HomeAssistantSession {
  func credentialSnapshot() -> HomeAssistantCredentialSnapshot {
    let availability: HomeAssistantCredentialSnapshot.Availability
    if rejectedCredentialGeneration != nil {
      availability = .rejected
    } else if credentials != nil {
      availability = .ready
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
    generation: Int,
    authenticationOperationEpoch: Int
  ) async throws {
    let refreshed = HomeAssistantCredentialUpdates.refreshed(original, token, successfulURL)
    try validateRefreshOperation(authenticationOperationEpoch)
    if credentials == refreshed { return }
    guard credentialGeneration == generation, credentials == original else {
      throw HomeAssistantAPIError.staleOperation
    }
    try await withHomeAssistantPersistence(gate: persistenceGate) {
      try validateRefreshOperation(authenticationOperationEpoch)
      if credentials == refreshed { return }
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
      guard
        self.authenticationOperationEpoch == authenticationOperationEpoch,
        pendingReplacementOperationEpoch == nil,
        credentialGeneration == generation,
        credentials == original
      else {
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

  private func validateRefreshOperation(_ operationEpoch: Int) throws {
    guard
      authenticationOperationEpoch == operationEpoch,
      pendingReplacementOperationEpoch == nil
    else {
      throw HomeAssistantAPIError.staleOperation
    }
  }

  func reserveCredentialGeneration() -> Int {
    credentialGeneration += 1
    authenticationOperationEpoch += 1
    pendingReplacementOperationEpoch = authenticationOperationEpoch
    return credentialGeneration
  }

  private func commitAuthenticationReplacement() {
    authenticationSessionEpoch += 1
    rejectedCredentialGeneration = nil
    successfulRouteSourceGeneration = nil
  }

  func finishAuthenticationReplacement(operationEpoch: Int) {
    guard pendingReplacementOperationEpoch == operationEpoch else { return }
    pendingReplacementOperationEpoch = nil
  }

  func reconcilePersistedCredentials(
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
    pendingReplacementOperationEpoch = nil
    await publishCredentialSnapshot()
  }

  func checkPersistenceCancellation(
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

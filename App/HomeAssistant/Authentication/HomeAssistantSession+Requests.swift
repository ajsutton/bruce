import Foundation

struct HomeAssistantDisconnectContext: Sendable {
  let credentials: HomeAssistantCredentials?
  fileprivate let generation: Int
}

extension HomeAssistantSession {
  func disconnect() async throws {
    let context = try await beginDisconnect()
    try await completeDisconnect(context)
  }

  func beginDisconnect() async throws -> HomeAssistantDisconnectContext {
    guard !isDisconnecting else { throw HomeAssistantAPIError.staleOperation }
    isDisconnecting = true
    let generation = reserveCredentialGeneration()
    let context = HomeAssistantDisconnectContext(
      credentials: credentials,
      generation: generation
    )
    await tokenRefresher.cancel()
    await transport.cancelAll()
    return context
  }

  func completeDisconnect(_ context: HomeAssistantDisconnectContext) async throws {
    defer { isDisconnecting = false }
    try await withHomeAssistantPersistence(gate: persistenceGate) {
      try await credentialStore.delete()
      guard credentialGeneration == context.generation else {
        _ = try await HomeAssistantCredentialRecovery.repair(
          credentials,
          replacing: nil,
          in: credentialStore
        )
        throw HomeAssistantAPIError.staleOperation
      }
    }
    credentials = nil
    authenticationSessionEpoch += 1
    rejectedCredentialGeneration = nil
    successfulRouteSourceGeneration = nil
    await publishCredentialSnapshot()
  }

  func currentCredentials() -> HomeAssistantCredentials? { credentials }

  func connectionSnapshot() -> HomeAssistantCredentialSnapshot {
    credentialSnapshot()
  }

  func performRequest(
    path: String,
    queryItems: [URLQueryItem] = [],
    body: Data?,
    canRefreshAfterUnauthorized: Bool,
    routeSelection: RouteSelection = .ordered
  ) async throws -> Data {
    guard !isDisconnecting else { throw HomeAssistantAPIError.noCredentials }
    guard let credentials else {
      throw HomeAssistantAPIError.noCredentials
    }
    let generation = credentialGeneration
    let sessionEpoch = authenticationSessionEpoch
    do {
      let response = try await loadResponse(
        path: path,
        queryItems: queryItems,
        body: body,
        credentials: credentials,
        routeSelection: routeSelection
      )
      try Task.checkCancellation()
      if body == nil {
        try await rememberSuccessful(
          response.baseURL,
          original: credentials,
          generation: generation
        )
      }
      return response.data
    } catch HomeAssistantAPIError.unauthorized {
      guard canRefreshAfterUnauthorized else {
        try await rejectExhaustedUnauthorized(
          credentials: credentials,
          sessionEpoch: sessionEpoch
        )
      }
      guard authenticationSessionEpoch == sessionEpoch else {
        throw HomeAssistantAPIError.staleOperation
      }
      guard let currentCredentials = self.credentials else {
        throw HomeAssistantAPIError.noCredentials
      }
      if currentCredentials.accessToken == credentials.accessToken {
        try await refreshIfNeeded(force: true)
      }
      return try await performRequest(
        path: path,
        queryItems: queryItems,
        body: body,
        canRefreshAfterUnauthorized: false,
        routeSelection: routeSelection
      )
    }
  }

  private func rejectExhaustedUnauthorized(
    credentials: HomeAssistantCredentials,
    sessionEpoch: Int
  ) async throws -> Never {
    guard authenticationSessionEpoch == sessionEpoch else {
      throw HomeAssistantAPIError.staleOperation
    }
    if self.credentials?.accessToken == credentials.accessToken {
      try await rejectCredentials(generation: credentialGeneration)
    }
    throw HomeAssistantAPIError.unauthorized
  }

  func checkConnection(
    validate: @escaping @Sendable (Data) throws -> Void
  ) async throws -> Data {
    try await refreshIfNeeded(force: false)
    return try await performRequest(
      path: "api/",
      body: nil,
      canRefreshAfterUnauthorized: true,
      routeSelection: .firstValid(validate)
    )
  }

  func authenticatedGET(
    path: String,
    queryItems: [URLQueryItem] = []
  ) async throws -> Data {
    try await refreshIfNeeded(force: false)
    return try await performRequest(
      path: path,
      queryItems: queryItems,
      body: nil,
      canRefreshAfterUnauthorized: true
    )
  }

  func authenticatedPOST(path: String, body: Data) async throws -> Data {
    try await refreshIfNeeded(force: false)
    return try await performRequest(
      path: path,
      body: body,
      canRefreshAfterUnauthorized: true
    )
  }

  func authenticatedWebSocketAccesses() async throws -> [HomeAssistantWebSocketAccess] {
    guard !isDisconnecting else { throw HomeAssistantAPIError.noCredentials }
    try await refreshIfNeeded(force: false)
    guard let credentials else {
      throw HomeAssistantAPIError.noCredentials
    }
    return try HomeAssistantWebSocketAccess.candidates(
      credentials: credentials,
      credentialGeneration: credentialGeneration,
      authenticationSessionEpoch: authenticationSessionEpoch
    )
  }

  func refreshRejectedWebSocketAccess(
    _ access: HomeAssistantWebSocketAccess
  ) async throws {
    guard let credentials,
      access.authenticationSessionEpoch == authenticationSessionEpoch
    else {
      throw HomeAssistantAPIError.staleOperation
    }
    guard credentials.accessToken == access.accessToken else { return }
    try await refreshIfNeeded(force: true)
  }

  func rejectWebSocketAccess(_ access: HomeAssistantWebSocketAccess) async throws {
    guard
      let credentials,
      access.authenticationSessionEpoch == authenticationSessionEpoch,
      access.accessToken == credentials.accessToken
    else { throw HomeAssistantAPIError.staleOperation }
    try await rejectCredentials(generation: credentialGeneration)
  }

  func rememberSuccessfulWebSocketAccess(
    _ access: HomeAssistantWebSocketAccess
  ) async throws {
    guard let credentials else {
      throw HomeAssistantAPIError.noCredentials
    }
    guard access.authenticationSessionEpoch == authenticationSessionEpoch else {
      throw HomeAssistantAPIError.staleOperation
    }
    guard
      access.accessToken == credentials.accessToken,
      access.credentialGeneration == credentialGeneration
    else { return }
    do {
      try await rememberSuccessful(
        access.baseURL,
        original: credentials,
        generation: access.credentialGeneration
      )
    } catch HomeAssistantAPIError.staleOperation {
      guard access.authenticationSessionEpoch == authenticationSessionEpoch else {
        throw HomeAssistantAPIError.staleOperation
      }
    }
  }

  func currentWebSocketAccesses() throws -> [HomeAssistantWebSocketAccess] {
    guard !isDisconnecting else { throw HomeAssistantAPIError.noCredentials }
    guard let credentials else { throw HomeAssistantAPIError.noCredentials }
    return try HomeAssistantWebSocketAccess.candidates(
      credentials: credentials,
      credentialGeneration: credentialGeneration,
      authenticationSessionEpoch: authenticationSessionEpoch
    )
  }

  func validateWebSocketAccess(_ access: HomeAssistantWebSocketAccess) throws {
    guard credentials != nil,
      access.authenticationSessionEpoch == authenticationSessionEpoch
    else {
      throw HomeAssistantAPIError.staleOperation
    }
  }
}

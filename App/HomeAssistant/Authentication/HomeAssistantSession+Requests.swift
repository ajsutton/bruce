import Foundation

struct HomeAssistantDisconnectContext: Sendable {
  let credentials: HomeAssistantCredentials?
  fileprivate let generation: Int
  fileprivate let operationEpoch: Int
}

private struct HomeAssistantUnauthorizedRequest: Sendable {
  let path: String
  let queryItems: [URLQueryItem]
  let body: Data?
  let canRefresh: Bool
  let routeSelection: RouteSelection
  let credentials: HomeAssistantCredentials
  let sessionEpoch: Int
  let operationEpoch: Int
}

extension HomeAssistantSession {
  func disconnect() async throws {
    let context = try await beginDisconnect()
    try await completeDisconnect(context)
  }

  func beginDisconnect() async throws -> HomeAssistantDisconnectContext {
    guard !isDisconnecting else { throw HomeAssistantAPIError.staleOperation }
    try await settleCredentialRejectionBeforeReplacement()
    isDisconnecting = true
    let generation = reserveCredentialGeneration()
    let context = HomeAssistantDisconnectContext(
      credentials: credentials,
      generation: generation,
      operationEpoch: authenticationOperationEpoch
    )
    await tokenRefresher.cancel()
    await transport.cancelAll()
    return context
  }

  func completeDisconnect(_ context: HomeAssistantDisconnectContext) async throws {
    defer {
      isDisconnecting = false
      finishAuthenticationReplacement(operationEpoch: context.operationEpoch)
    }
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
    finishAuthenticationReplacement(operationEpoch: context.operationEpoch)
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
    if rejectedCredentialGeneration != nil {
      throw HomeAssistantAPIError.reauthenticationRequired
    }
    guard pendingReplacementOperationEpoch == nil else {
      throw HomeAssistantAPIError.staleOperation
    }
    guard let credentials else {
      throw HomeAssistantAPIError.noCredentials
    }
    let generation = credentialGeneration
    let sessionEpoch = authenticationSessionEpoch
    let operationEpoch = authenticationOperationEpoch
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
        try await completeRead(
          response,
          credentials: credentials,
          generation: generation,
          sessionEpoch: sessionEpoch,
          operationEpoch: operationEpoch
        )
      }
      return response.data
    } catch HomeAssistantAPIError.unauthorized {
      return try await recoverFromUnauthorized(
        HomeAssistantUnauthorizedRequest(
          path: path,
          queryItems: queryItems,
          body: body,
          canRefresh: canRefreshAfterUnauthorized,
          routeSelection: routeSelection,
          credentials: credentials,
          sessionEpoch: sessionEpoch,
          operationEpoch: operationEpoch
        )
      )
    }
  }

  private func recoverFromUnauthorized(
    _ request: HomeAssistantUnauthorizedRequest
  ) async throws -> Data {
    guard
      authenticationSessionEpoch == request.sessionEpoch,
      authenticationOperationEpoch == request.operationEpoch
    else {
      throw HomeAssistantAPIError.staleOperation
    }
    guard request.canRefresh else {
      try await rejectExhaustedUnauthorized(
        credentials: request.credentials,
        sessionEpoch: request.sessionEpoch,
        operationEpoch: request.operationEpoch
      )
    }
    guard let currentCredentials = self.credentials else {
      throw HomeAssistantAPIError.noCredentials
    }
    if currentCredentials.accessToken == request.credentials.accessToken {
      try await refreshIfNeeded(force: true)
    }
    return try await performRequest(
      path: request.path,
      queryItems: request.queryItems,
      body: request.body,
      canRefreshAfterUnauthorized: false,
      routeSelection: request.routeSelection
    )
  }

  private func completeRead(
    _ response: HomeAssistantAuthenticatedResponse,
    credentials: HomeAssistantCredentials,
    generation: Int,
    sessionEpoch: Int,
    operationEpoch: Int
  ) async throws {
    guard
      authenticationSessionEpoch == sessionEpoch,
      authenticationOperationEpoch == operationEpoch
    else {
      throw HomeAssistantAPIError.staleOperation
    }
    try await rememberSuccessful(
      response.baseURL,
      original: credentials,
      generation: generation,
      authenticationSessionEpoch: sessionEpoch,
      authenticationOperationEpoch: operationEpoch
    )
  }

  private func rejectExhaustedUnauthorized(
    credentials: HomeAssistantCredentials,
    sessionEpoch: Int,
    operationEpoch: Int
  ) async throws -> Never {
    guard
      authenticationSessionEpoch == sessionEpoch,
      authenticationOperationEpoch == operationEpoch
    else {
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
    guard pendingReplacementOperationEpoch == nil else {
      throw HomeAssistantAPIError.staleOperation
    }
    try await refreshIfNeeded(force: false)
    guard let credentials else {
      throw HomeAssistantAPIError.noCredentials
    }
    return try HomeAssistantWebSocketAccess.candidates(
      credentials: credentials,
      credentialGeneration: credentialGeneration,
      authenticationSessionEpoch: authenticationSessionEpoch,
      authenticationOperationEpoch: authenticationOperationEpoch
    )
  }

  func refreshRejectedWebSocketAccess(
    _ access: HomeAssistantWebSocketAccess
  ) async throws {
    guard let credentials,
      access.authenticationSessionEpoch == authenticationSessionEpoch,
      access.authenticationOperationEpoch == authenticationOperationEpoch
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
      access.authenticationOperationEpoch == authenticationOperationEpoch,
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
    guard
      access.authenticationSessionEpoch == authenticationSessionEpoch,
      access.authenticationOperationEpoch == authenticationOperationEpoch
    else {
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
        generation: access.credentialGeneration,
        authenticationSessionEpoch: access.authenticationSessionEpoch,
        authenticationOperationEpoch: access.authenticationOperationEpoch
      )
    } catch HomeAssistantAPIError.staleOperation {
      guard
        access.authenticationSessionEpoch == authenticationSessionEpoch,
        access.authenticationOperationEpoch == authenticationOperationEpoch
      else {
        throw HomeAssistantAPIError.staleOperation
      }
    }
  }

  func currentWebSocketAccesses() throws -> [HomeAssistantWebSocketAccess] {
    guard !isDisconnecting else { throw HomeAssistantAPIError.noCredentials }
    guard rejectedCredentialGeneration == nil else {
      throw HomeAssistantAPIError.reauthenticationRequired
    }
    guard pendingReplacementOperationEpoch == nil else {
      throw HomeAssistantAPIError.staleOperation
    }
    guard let credentials else { throw HomeAssistantAPIError.noCredentials }
    return try HomeAssistantWebSocketAccess.candidates(
      credentials: credentials,
      credentialGeneration: credentialGeneration,
      authenticationSessionEpoch: authenticationSessionEpoch,
      authenticationOperationEpoch: authenticationOperationEpoch
    )
  }

  func validateWebSocketAccess(_ access: HomeAssistantWebSocketAccess) throws {
    guard rejectedCredentialGeneration == nil else {
      throw HomeAssistantAPIError.reauthenticationRequired
    }
    guard credentials != nil,
      access.authenticationSessionEpoch == authenticationSessionEpoch,
      access.authenticationOperationEpoch == authenticationOperationEpoch
    else {
      throw HomeAssistantAPIError.staleOperation
    }
  }
}

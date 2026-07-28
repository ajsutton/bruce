import Foundation

struct HomeAssistantWebSocketAccess: Sendable {
  let baseURL: URL
  let url: URL
  let accessToken: String
  let credentialGeneration: Int
}

actor HomeAssistantSession {
  private let credentialStore: any HomeAssistantCredentialStoring
  private let transport: HomeAssistantAuthenticatedTransport
  private let tokenRefresher: HomeAssistantTokenRefresher
  private let now: @Sendable () -> Date
  private let refreshLeeway: TimeInterval
  private let persistenceGate: HomeAssistantPersistenceGate

  private var credentials: HomeAssistantCredentials?
  private var credentialGeneration = 0
  private var authenticationSessionEpoch = 0
  private var rejectedCredentialGeneration: Int?, successfulRouteSourceGeneration: Int?

  init(
    credentialStore: any HomeAssistantCredentialStoring,
    authenticationClient: HomeAssistantAuthenticationClient,
    loader: any HomeAssistantHTTPDataLoading,
    now: @escaping @Sendable () -> Date = Date.init,
    refreshLeeway: TimeInterval = 60,
    persistenceGate: HomeAssistantPersistenceGate = HomeAssistantPersistenceGate()
  ) {
    self.credentialStore = credentialStore
    transport = HomeAssistantAuthenticatedTransport(loader: loader)
    tokenRefresher = HomeAssistantTokenRefresher(authenticationClient: authenticationClient)
    self.now = now
    self.refreshLeeway = refreshLeeway
    self.persistenceGate = persistenceGate
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
      return credentials != nil
    }
  }

  func install(_ newCredentials: HomeAssistantCredentials) async throws {
    let generation = reserveCredentialGeneration()
    await tokenRefresher.cancel()
    try await withHomeAssistantPersistence(gate: persistenceGate) {
      try await credentialStore.save(newCredentials)
      try await HomeAssistantCredentialRecovery.checkCancellation(
        credentials: credentials,
        store: credentialStore
      )
      guard credentialGeneration == generation else {
        try await HomeAssistantCredentialRecovery.repair(credentials, in: credentialStore)
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = newCredentials
    }
  }

  func verifyAndInstall(
    _ newCredentials: HomeAssistantCredentials,
    validate: @escaping @Sendable (Data) throws -> Void
  ) async throws {
    let generation = reserveCredentialGeneration()
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
      try await HomeAssistantCredentialRecovery.checkCancellation(
        credentials: credentials,
        store: credentialStore
      )
      guard credentialGeneration == generation else {
        try await HomeAssistantCredentialRecovery.repair(credentials, in: credentialStore)
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = verifiedCredentials
    }
  }

  func currentCredentials() -> HomeAssistantCredentials? { credentials }

  func disconnect() async throws {
    let disconnectedCredentials = credentials
    credentials = nil
    credentialGeneration += 1
    authenticationSessionEpoch += 1
    rejectedCredentialGeneration = nil
    successfulRouteSourceGeneration = nil
    let disconnectedGeneration = credentialGeneration
    await tokenRefresher.cancel()
    await transport.cancelAll()
    do {
      try await withHomeAssistantPersistence(gate: persistenceGate) {
        try await credentialStore.delete()
        if credentialGeneration != disconnectedGeneration {
          try await HomeAssistantCredentialRecovery.repair(credentials, in: credentialStore)
        }
      }
    } catch {
      credentials =
        credentialGeneration == disconnectedGeneration ? disconnectedCredentials : credentials
      throw error
    }
  }

  private func refreshIfNeeded(force: Bool) async throws {
    guard let credentials else {
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
      try await credentialStore.save(refreshed)
      try await HomeAssistantCredentialRecovery.checkCancellation(
        credentials: credentials,
        store: credentialStore
      )
      guard credentialGeneration == generation, credentials == original else {
        try await HomeAssistantCredentialRecovery.repair(credentials, in: credentialStore)
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = refreshed
      successfulRouteSourceGeneration = nil
      credentialGeneration += 1
    }
  }

  private func rejectCredentials(generation: Int) async throws -> Never {
    if credentials == nil, rejectedCredentialGeneration == generation {
      throw HomeAssistantAPIError.reauthenticationRequired
    }
    guard credentialGeneration == generation else {
      throw HomeAssistantAPIError.staleOperation
    }
    credentials = nil
    credentialGeneration += 1
    authenticationSessionEpoch += 1
    rejectedCredentialGeneration = generation
    successfulRouteSourceGeneration = nil
    let rejectedGeneration = credentialGeneration
    try await withHomeAssistantPersistence(gate: persistenceGate) {
      try await credentialStore.delete()
      if credentialGeneration != rejectedGeneration {
        try await HomeAssistantCredentialRecovery.repair(credentials, in: credentialStore)
        throw HomeAssistantAPIError.staleOperation
      }
    }
    throw HomeAssistantAPIError.reauthenticationRequired
  }

  private func rememberSuccessful(
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
        try await HomeAssistantCredentialRecovery.repair(credentials, in: credentialStore)
        throw HomeAssistantAPIError.staleOperation
      }
      try await credentialStore.save(updated)
      try await HomeAssistantCredentialRecovery.checkCancellation(
        credentials: credentials,
        store: credentialStore
      )
      guard credentialGeneration == generation, credentials == original else {
        try await HomeAssistantCredentialRecovery.repair(credentials, in: credentialStore)
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = updated
      successfulRouteSourceGeneration = generation
      credentialGeneration += 1
    }
  }

  private func reserveCredentialGeneration() -> Int {
    credentialGeneration += 1
    authenticationSessionEpoch += 1
    rejectedCredentialGeneration = nil
    successfulRouteSourceGeneration = nil
    return credentialGeneration
  }

}

extension HomeAssistantSession {
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

  func authenticatedGET(path: String) async throws -> Data {
    try await refreshIfNeeded(force: false)
    return try await performRequest(
      path: path,
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

  private func performRequest(
    path: String,
    body: Data?,
    canRefreshAfterUnauthorized: Bool,
    routeSelection: RouteSelection = .ordered
  ) async throws -> Data {
    guard let credentials else {
      throw HomeAssistantAPIError.noCredentials
    }
    let generation = credentialGeneration
    let sessionEpoch = authenticationSessionEpoch
    do {
      let response = try await loadResponse(
        path: path,
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
        throw HomeAssistantAPIError.unauthorized
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
        body: body,
        canRefreshAfterUnauthorized: false,
        routeSelection: routeSelection
      )
    }
  }

  private func loadResponse(
    path: String,
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
    return try await transport.get(path: path, credentials: credentials)
  }

  func authenticatedWebSocketAccess() async throws -> HomeAssistantWebSocketAccess {
    guard let access = try await authenticatedWebSocketAccesses().first else {
      throw HomeAssistantAPIError.invalidServerURL
    }
    return access
  }

  func authenticatedWebSocketAccesses() async throws -> [HomeAssistantWebSocketAccess] {
    try await refreshIfNeeded(force: false)
    guard let credentials else {
      throw HomeAssistantAPIError.noCredentials
    }
    return try HomeAssistantRequestRouter.candidates(for: credentials).map { baseURL in
      HomeAssistantWebSocketAccess(
        baseURL: baseURL,
        url: try HomeAssistantRequestRouter.webSocketURL(baseURL: baseURL),
        accessToken: credentials.accessToken,
        credentialGeneration: credentialGeneration
      )
    }
  }

  func rememberSuccessfulWebSocketAccess(
    _ access: HomeAssistantWebSocketAccess
  ) async throws {
    guard let credentials else {
      throw HomeAssistantAPIError.noCredentials
    }
    guard
      access.accessToken == credentials.accessToken,
      access.credentialGeneration == credentialGeneration
    else {
      throw HomeAssistantAPIError.staleOperation
    }
    try await rememberSuccessful(
      access.baseURL,
      original: credentials,
      generation: access.credentialGeneration
    )
  }
}

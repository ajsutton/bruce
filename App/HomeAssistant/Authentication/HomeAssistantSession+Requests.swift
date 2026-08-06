import Foundation

extension HomeAssistantSession {
  func performRequest(
    path: String,
    queryItems: [URLQueryItem] = [],
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
        queryItems: queryItems,
        body: body,
        canRefreshAfterUnauthorized: false,
        routeSelection: routeSelection
      )
    }
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

  func validateWebSocketAccess(_ access: HomeAssistantWebSocketAccess) throws {
    guard credentials != nil,
      access.authenticationSessionEpoch == authenticationSessionEpoch
    else {
      throw HomeAssistantAPIError.staleOperation
    }
  }
}

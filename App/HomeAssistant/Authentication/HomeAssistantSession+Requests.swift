import Foundation

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
}

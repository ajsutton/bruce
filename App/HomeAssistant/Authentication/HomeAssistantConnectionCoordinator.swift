import Foundation

@MainActor
protocol HomeAssistantConnecting: AnyObject {
  func connect(to candidate: HomeAssistantConnectionCandidate) async throws
    -> HomeAssistantCredentials
  func restore() async throws -> HomeAssistantCredentials?
  func testConnection() async throws -> HomeAssistantCredentials
  func disconnect() async throws
  func cancel()
}

@MainActor
final class HomeAssistantConnectionCoordinator: HomeAssistantConnecting {
  private let authenticationClient: HomeAssistantAuthenticationClient
  private let browser: any HomeAssistantWebAuthenticating
  private let session: HomeAssistantSession

  init(
    authenticationClient: HomeAssistantAuthenticationClient,
    browser: any HomeAssistantWebAuthenticating,
    session: HomeAssistantSession
  ) {
    self.authenticationClient = authenticationClient
    self.browser = browser
    self.session = session
  }

  func connect(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    let request = try authenticationClient.authorizationRequest(for: candidate.activeURL)
    let callback = try await browser.authenticate(at: request.url)
    try Task.checkCancellation()
    let code = try authenticationClient.authorizationCode(
      from: callback,
      expectedState: request.state
    )
    let token = try await authenticationClient.exchangeCode(code, at: candidate.activeURL)
    try Task.checkCancellation()
    guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
      throw HomeAssistantAuthenticationError.invalidTokenResponse
    }
    let credentials = HomeAssistantCredentials(
      instanceID: candidate.instanceID,
      instanceName: candidate.name,
      internalURL: candidate.internalURL,
      externalURL: candidate.externalURL,
      lastSuccessfulURL: candidate.activeURL,
      accessToken: token.accessToken,
      refreshToken: refreshToken,
      tokenType: token.tokenType,
      accessTokenExpiresAt: token.expiresAt,
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
    try await session.verifyAndInstall(credentials) { data in
      _ = try HomeAssistantAPIClient.status(from: data)
    }
    guard let installedCredentials = await session.currentCredentials() else {
      throw HomeAssistantAPIError.noCredentials
    }
    return installedCredentials
  }

  func restore() async throws -> HomeAssistantCredentials? {
    _ = try await session.restore()
    return await session.currentCredentials()
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    let client = HomeAssistantAPIClient(session: session)
    do {
      _ = try await client.checkConnection()
    } catch {
      guard Self.shouldRetryConnectionCheck(after: error) else { throw error }
      try Task.checkCancellation()
      _ = try await client.checkConnection()
    }
    guard let credentials = await session.currentCredentials() else {
      throw HomeAssistantAPIError.noCredentials
    }
    return credentials
  }

  func disconnect() async throws {
    browser.cancel()
    if let credentials = await session.currentCredentials() {
      try await revokeWhenReachable(credentials)
    }
    try Task.checkCancellation()
    try await session.disconnect()
  }

  func cancel() {
    browser.cancel()
  }

  private func revokeWhenReachable(_ credentials: HomeAssistantCredentials) async throws {
    let knownURLs = [
      credentials.lastSuccessfulURL, credentials.internalURL, credentials.externalURL,
    ]
    .compactMap(\.self)
    .reduce(into: [URL]()) { result, url in
      let isConfirmedInternal =
        url == credentials.internalURL
        && ["http", "https"].contains(url.scheme?.lowercased())
      let isConfirmedExternal =
        url == credentials.externalURL
        && url.scheme?.lowercased() == "https"
      guard isConfirmedInternal || isConfirmedExternal, !result.contains(url) else {
        return
      }
      result.append(url)
    }
    for (index, url) in knownURLs.enumerated() {
      do {
        try await authenticationClient.revoke(
          refreshToken: credentials.refreshToken,
          at: url
        )
        return
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        guard Self.isConnectivityFailure(error), index + 1 < knownURLs.count else {
          return
        }
      }
    }
  }

  private static func isConnectivityFailure(_ error: any Error) -> Bool {
    guard let error = error as? URLError else {
      return false
    }
    return [
      .cannotFindHost,
      .cannotConnectToHost,
      .dnsLookupFailed,
      .networkConnectionLost,
      .notConnectedToInternet,
      .timedOut,
    ].contains(error.code)
  }

  private static func shouldRetryConnectionCheck(after error: any Error) -> Bool {
    if case HomeAssistantAPIError.staleOperation = error {
      return true
    }
    return HomeAssistantRequestRouter.isConnectivityFailure(error)
  }
}

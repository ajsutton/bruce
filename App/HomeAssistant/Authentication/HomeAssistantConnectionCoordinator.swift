import Foundation

@MainActor
protocol HomeAssistantConnecting: AnyObject {
  func authenticate(to candidate: HomeAssistantConnectionCandidate) async throws
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
  private let supervisor: any HomeAssistantConnectionSupervising
  private let requireFeatureData: @Sendable () async throws -> Void
  private var revocationTask: Task<Void, Never>?

  deinit {
    revocationTask?.cancel()
  }

  init(
    authenticationClient: HomeAssistantAuthenticationClient,
    browser: any HomeAssistantWebAuthenticating,
    session: HomeAssistantSession,
    supervisor: any HomeAssistantConnectionSupervising,
    requireFeatureData: (@Sendable () async throws -> Void)? = nil
  ) {
    self.authenticationClient = authenticationClient
    self.browser = browser
    self.session = session
    self.supervisor = supervisor
    self.requireFeatureData =
      requireFeatureData ?? {
        try await supervisor.requireFreshLiveData()
      }
  }

  func authenticate(
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
    try await requireFeatureData()
    try Task.checkCancellation()
    guard let credentials = await session.currentCredentials() else {
      throw HomeAssistantAPIError.noCredentials
    }
    return credentials
  }

  func disconnect() async throws {
    browser.cancel()
    revocationTask?.cancel()
    let disconnectContext = try await session.beginDisconnect()
    let preparationID = await supervisor.prepareForDisconnect()
    let credentials = disconnectContext.credentials
    let localDisconnect = Task { try await session.completeDisconnect(disconnectContext) }
    do {
      try await localDisconnect.value
    } catch {
      await supervisor.recoverFromFailedDisconnect(preparationID: preparationID)
      throw error
    }
    await supervisor.stop()
    guard let credentials else { return }
    let authenticationClient = authenticationClient
    revocationTask = Task { [weak self] in
      try? await Self.revokeWhenReachable(
        credentials,
        authenticationClient: authenticationClient
      )
      guard !Task.isCancelled else { return }
      self?.revocationTask = nil
    }
  }

  func cancel() {
    browser.cancel()
    revocationTask?.cancel()
    revocationTask = nil
  }

  private static func revokeWhenReachable(
    _ credentials: HomeAssistantCredentials,
    authenticationClient: HomeAssistantAuthenticationClient
  ) async throws {
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

}

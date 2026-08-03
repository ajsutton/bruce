import Foundation

struct WidgetHomeEnergyClient: Sendable {
  private let session: URLSession
  private let now: @Sendable () -> Date
  private let loadCredentials: @Sendable () throws -> WidgetHomeAssistantCredentials?
  private let persistCredentials:
    @Sendable (
      WidgetHomeAssistantCredentials,
      WidgetHomeAssistantCredentials
    ) throws -> Void
  private let loadDailyTotals:
    @Sendable (WidgetHomeAssistantCredentials) async throws -> WidgetDailyEnergyTotals

  init(
    session: URLSession = .shared,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.session = session
    self.now = now
    loadCredentials = { try WidgetHomeAssistantCredentialStore().load() }
    persistCredentials = { credentials, originalCredentials in
      _ = try WidgetHomeAssistantCredentialStore().save(
        credentials,
        replacing: originalCredentials
      )
    }
    loadDailyTotals = {
      try await WidgetDailyEnergyClient(session: session, now: now)
        .loadTotals(using: $0)
    }
  }

  init(
    session: URLSession,
    now: @escaping @Sendable () -> Date,
    loadCredentials: @escaping @Sendable () throws -> WidgetHomeAssistantCredentials?,
    persistCredentials:
      @escaping @Sendable (
        WidgetHomeAssistantCredentials,
        WidgetHomeAssistantCredentials
      ) throws -> Void = { _, _ in },
    loadDailyTotals:
      @escaping @Sendable (WidgetHomeAssistantCredentials) async throws
      -> WidgetDailyEnergyTotals
  ) {
    self.session = session
    self.now = now
    self.loadCredentials = loadCredentials
    self.persistCredentials = persistCredentials
    self.loadDailyTotals = loadDailyTotals
  }

  func loadSnapshot(
    previous: HomeEnergyWidgetSnapshot? = nil
  ) async throws -> HomeEnergyWidgetSnapshot {
    let capturedAt = now()
    guard var credentials = try loadCredentials() else {
      throw WidgetHomeEnergyError.credentialsUnavailable
    }
    let matchingPrevious =
      previous?.sourceIdentifier == credentials.sourceIdentifier
      ? previous : nil
    if credentials.accessTokenExpiresAt <= now().addingTimeInterval(60) {
      credentials = try await refresh(credentials)
    }

    var components = try await loadComponents(using: credentials)
    if components.needsAuthenticationRefresh {
      do {
        credentials = try await refresh(credentials)
        let refreshedComponents = try await loadComponents(using: credentials)
        components = refreshedComponents.preservingSuccesses(from: components)
      } catch {
        try Self.checkCancellation(error)
        if !components.hasSuccess { throw error }
      }
    }
    guard
      let snapshot = Self.snapshot(
        from: components,
        previous: matchingPrevious,
        capturedAt: capturedAt,
        sourceIdentifier: credentials.sourceIdentifier
      )
    else {
      throw components.failure ?? WidgetHomeEnergyError.noReachableServer
    }
    return snapshot
  }

  private func loadComponents(
    using credentials: WidgetHomeAssistantCredentials
  ) async throws -> WidgetHomeEnergyComponents {
    async let states = capture { try await loadStates(using: credentials) }
    async let dailyTotals = capture {
      try await loadDailyTotals(credentials)
    }
    return try await WidgetHomeEnergyComponents(states: states, dailyTotals: dailyTotals)
  }

  private func loadStates(
    using credentials: WidgetHomeAssistantCredentials
  ) async throws -> [WidgetHomeAssistantState] {
    var receivedUnauthorized = false
    var receivedInvalidResponse = false
    for baseURL in credentials.candidateURLs {
      do {
        var request = URLRequest(
          url: baseURL.appending(path: "api/states"),
          timeoutInterval: 8
        )
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { continue }
        if response.statusCode == 401 {
          receivedUnauthorized = true
          continue
        }
        guard response.statusCode == 200 else { continue }
        guard let states = try? JSONDecoder().decode([WidgetHomeAssistantState].self, from: data)
        else {
          receivedInvalidResponse = true
          continue
        }
        BruceSharedHomeAssistant.rememberWidgetRoute(
          baseURL,
          for: credentials.sourceIdentifier
        )
        return states
      } catch {
        try Self.checkCancellation(error)
        continue
      }
    }
    if receivedUnauthorized { throw WidgetHomeEnergyError.unauthorized }
    if receivedInvalidResponse { throw WidgetHomeEnergyError.invalidResponse }
    throw WidgetHomeEnergyError.noReachableServer
  }

  private func refresh(
    _ credentials: WidgetHomeAssistantCredentials
  ) async throws -> WidgetHomeAssistantCredentials {
    for baseURL in credentials.candidateURLs {
      do {
        let endpoint = baseURL.appending(path: "auth/token")
        var request = URLRequest(url: endpoint, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue(
          "application/x-www-form-urlencoded",
          forHTTPHeaderField: "Content-Type"
        )
        var components = URLComponents()
        components.queryItems = [
          URLQueryItem(name: "grant_type", value: "refresh_token"),
          URLQueryItem(name: "refresh_token", value: credentials.refreshToken),
          URLQueryItem(name: "client_id", value: credentials.clientID.absoluteString),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
          let token = try? JSONDecoder().decode(WidgetHomeAssistantToken.self, from: data)
        else {
          continue
        }
        var refreshed = credentials
        refreshed.accessToken = token.accessToken
        refreshed.refreshToken = token.refreshToken ?? credentials.refreshToken
        refreshed.accessTokenExpiresAt = now().addingTimeInterval(token.expiresIn)
        refreshed.lastSuccessfulURL = baseURL
        try persistCredentials(refreshed, credentials)
        BruceSharedHomeAssistant.rememberWidgetRoute(
          baseURL,
          for: credentials.sourceIdentifier
        )
        return refreshed
      } catch {
        try Self.checkCancellation(error)
        continue
      }
    }
    throw WidgetHomeEnergyError.noReachableServer
  }

  private func capture<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> WidgetHomeEnergyComponent<Value> {
    do {
      return .success(try await operation())
    } catch {
      try Self.checkCancellation(error)
      return .failure(error as? WidgetHomeEnergyError ?? .noReachableServer)
    }
  }

  private static func checkCancellation(_ error: Error) throws {
    if Task.isCancelled || (error as? URLError)?.code == .cancelled {
      throw CancellationError()
    }
  }

}

struct WidgetHomeAssistantState: Decodable, Sendable {
  let entityID: String
  let state: String
  fileprivate let attributes: WidgetHomeAssistantStateAttributes?

  var lastReset: Date? {
    guard let value = attributes?.lastReset else { return nil }
    return (try? Date(value, strategy: .iso8601))
      ?? (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
  }

  enum CodingKeys: String, CodingKey {
    case entityID = "entity_id"
    case state
    case attributes
  }
}

private struct WidgetHomeAssistantStateAttributes: Decodable, Sendable {
  let lastReset: String?

  enum CodingKeys: String, CodingKey {
    case lastReset = "last_reset"
  }
}

private struct WidgetHomeAssistantToken: Decodable {
  let accessToken: String
  let refreshToken: String?
  let expiresIn: TimeInterval

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
  }
}

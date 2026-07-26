import Foundation
import Security

struct HomeAssistantAuthorizationRequest: Equatable, Sendable {
  let url: URL
  let state: String
}

struct HomeAssistantToken: Equatable, Sendable {
  let accessToken: String
  let refreshToken: String?
  let tokenType: String
  let expiresAt: Date
}

struct HomeAssistantAuthenticationClient: Sendable {
  private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: TimeInterval
  }

  private struct ErrorResponse: Decodable {
    let errorDescription: String?
  }

  private let configuration: HomeAssistantOAuthConfiguration
  private let loader: any HomeAssistantHTTPDataLoading
  private let now: @Sendable () -> Date
  private let stateGenerator: @Sendable () throws -> String

  init(
    configuration: HomeAssistantOAuthConfiguration = .release,
    loader: any HomeAssistantHTTPDataLoading = URLSessionHomeAssistantHTTPDataLoader(),
    now: @escaping @Sendable () -> Date = Date.init,
    stateGenerator: @escaping @Sendable () throws -> String = Self.secureState
  ) {
    self.configuration = configuration
    self.loader = loader
    self.now = now
    self.stateGenerator = stateGenerator
  }

  func authorizationRequest(
    for instanceURL: URL
  ) throws -> HomeAssistantAuthorizationRequest {
    let state = try stateGenerator()
    let endpoint = try Self.endpoint("auth/authorize", relativeTo: instanceURL)
    guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
      throw HomeAssistantAuthenticationError.invalidInstanceURL
    }
    components.queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: configuration.clientID.absoluteString),
      URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
      URLQueryItem(name: "state", value: state),
    ]
    guard let url = components.url else {
      throw HomeAssistantAuthenticationError.invalidInstanceURL
    }
    return HomeAssistantAuthorizationRequest(url: url, state: state)
  }

  func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
    guard Self.matches(callbackURL, configuration.redirectURI),
      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
    else {
      throw HomeAssistantAuthenticationError.invalidCallback
    }
    let queryItems = components.queryItems ?? []
    let states = queryItems.filter { $0.name == "state" }.compactMap(\.value)
    let codes = queryItems.filter { $0.name == "code" }.compactMap(\.value)
    let errors = queryItems.filter { $0.name == "error" }.compactMap(\.value)
    let errorDescriptions =
      queryItems.filter { $0.name == "error_description" }.compactMap(\.value)
    guard states.count == 1 else {
      throw HomeAssistantAuthenticationError.invalidCallback
    }
    guard states[0] == expectedState else {
      throw HomeAssistantAuthenticationError.stateMismatch
    }
    guard errorDescriptions.count <= 1, codes.count <= 1, errors.count <= 1 else {
      throw HomeAssistantAuthenticationError.invalidCallback
    }
    if errors.count == 1, codes.isEmpty {
      throw HomeAssistantAuthenticationError.authorizationRejected(
        errorDescriptions.first ?? errors[0]
      )
    }
    guard errors.isEmpty else {
      throw HomeAssistantAuthenticationError.invalidCallback
    }
    guard let code = codes.first, !code.isEmpty else {
      throw HomeAssistantAuthenticationError.missingAuthorizationCode
    }
    return code
  }

  func exchangeCode(_ code: String, at instanceURL: URL) async throws -> HomeAssistantToken {
    try await tokenRequest(
      at: instanceURL,
      fields: [
        ("grant_type", "authorization_code"),
        ("code", code),
        ("client_id", configuration.clientID.absoluteString),
      ]
    )
  }

  func refresh(
    refreshToken: String,
    at instanceURL: URL
  ) async throws -> HomeAssistantToken {
    try await tokenRequest(
      at: instanceURL,
      fields: [
        ("grant_type", "refresh_token"),
        ("refresh_token", refreshToken),
        ("client_id", configuration.clientID.absoluteString),
      ]
    )
  }

  func revoke(refreshToken: String, at instanceURL: URL) async throws {
    let request = try Self.formRequest(
      endpoint: Self.endpoint("auth/token", relativeTo: instanceURL),
      fields: [
        ("action", "revoke"),
        ("token", refreshToken),
      ]
    )
    let (data, response) = try await loader.data(for: request)
    guard (200..<300).contains(response.statusCode) else {
      throw Self.serverError(data: data, statusCode: response.statusCode)
    }
  }

  private func tokenRequest(
    at instanceURL: URL,
    fields: [(String, String)]
  ) async throws -> HomeAssistantToken {
    let request = try Self.formRequest(
      endpoint: Self.endpoint("auth/token", relativeTo: instanceURL),
      fields: fields
    )
    let (data, response) = try await loader.data(for: request)
    guard (200..<300).contains(response.statusCode) else {
      throw Self.serverError(data: data, statusCode: response.statusCode)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let response = try? decoder.decode(TokenResponse.self, from: data),
      !response.accessToken.isEmpty,
      !response.tokenType.isEmpty,
      response.expiresIn > 0
    else {
      throw HomeAssistantAuthenticationError.invalidTokenResponse
    }
    return HomeAssistantToken(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      tokenType: response.tokenType,
      expiresAt: now().addingTimeInterval(response.expiresIn)
    )
  }

  private static func endpoint(_ path: String, relativeTo instanceURL: URL) throws -> URL {
    guard ["http", "https"].contains(instanceURL.scheme?.lowercased()),
      instanceURL.host() != nil,
      instanceURL.user == nil,
      instanceURL.password == nil,
      instanceURL.query == nil,
      instanceURL.fragment == nil
    else {
      throw HomeAssistantAuthenticationError.invalidInstanceURL
    }
    return instanceURL.appending(path: path)
  }

  private static func formRequest(
    endpoint: URL,
    fields: [(String, String)]
  ) throws -> URLRequest {
    var components = URLComponents()
    components.queryItems = fields.map(URLQueryItem.init)
    guard
      let body = components.percentEncodedQuery?.replacingOccurrences(of: "%20", with: "+")
        .data(using: .utf8)
    else {
      throw HomeAssistantAuthenticationError.invalidInstanceURL
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue(
      "application/x-www-form-urlencoded",
      forHTTPHeaderField: "Content-Type"
    )
    request.httpBody = body
    return request
  }

  private static func matches(_ callback: URL, _ redirect: URL) -> Bool {
    callback.scheme?.lowercased() == redirect.scheme?.lowercased()
      && callback.host()?.lowercased() == redirect.host()?.lowercased()
      && callback.port == redirect.port
      && callback.path == redirect.path
      && callback.user == nil
      && callback.password == nil
      && callback.fragment == nil
  }

  private static func serverError(
    data: Data,
    statusCode: Int
  ) -> HomeAssistantAuthenticationError {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let description = try? decoder.decode(ErrorResponse.self, from: data).errorDescription
    return .serverRejectedRequest(statusCode: statusCode, description: description)
  }

  private static func secureState() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw HomeAssistantAuthenticationError.randomGenerationFailed
    }
    return Data(bytes).base64EncodedString(
      options: [.endLineWithLineFeed]
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
  }
}

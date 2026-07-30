import Foundation

enum HomeAssistantRequestRouter {
  static func candidates(
    for credentials: HomeAssistantCredentials
  ) throws -> [URL] {
    let knownCandidates = [credentials.internalURL, credentials.externalURL].compactMap(\.self)
    let ordered = [credentials.lastSuccessfulURL] + knownCandidates
    let valid = ordered.reduce(into: [URL]()) { result, url in
      if !result.contains(url), isAllowed(url, by: credentials) {
        result.append(url)
      }
    }
    guard !valid.isEmpty else {
      throw HomeAssistantAPIError.invalidServerURL
    }
    return valid
  }

  static func authenticatedRequest(
    baseURL: URL,
    path: String,
    queryItems: [URLQueryItem] = [],
    token: String,
    method: String = "GET",
    body: Data? = nil
  ) throws -> URLRequest {
    guard !path.hasPrefix("http://"), !path.hasPrefix("https://") else {
      throw HomeAssistantAPIError.invalidServerURL
    }
    var components = URLComponents(
      url: baseURL.appending(path: path),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components?.url else {
      throw HomeAssistantAPIError.invalidServerURL
    }
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.httpMethod = method
    request.httpBody = body
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if body != nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return request
  }

  static func webSocketURL(baseURL: URL) throws -> URL {
    var components = URLComponents(
      url: baseURL.appending(path: "api/websocket"),
      resolvingAgainstBaseURL: false
    )
    switch components?.scheme?.lowercased() {
    case "http":
      components?.scheme = "ws"
    case "https":
      components?.scheme = "wss"
    default:
      throw HomeAssistantAPIError.invalidServerURL
    }
    guard let url = components?.url else {
      throw HomeAssistantAPIError.invalidServerURL
    }
    return url
  }

  static func isConnectivityFailure(_ error: any Error) -> Bool {
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

  static func isRejectedRefresh(_ error: any Error) -> Bool {
    guard
      case .serverRejectedRequest(let statusCode, _) =
        error as? HomeAssistantAuthenticationError
    else {
      return false
    }
    return statusCode == 400 || statusCode == 401
  }

  private static func isAllowed(
    _ url: URL,
    by credentials: HomeAssistantCredentials
  ) -> Bool {
    if url == credentials.internalURL {
      return ["http", "https"].contains(url.scheme?.lowercased())
    }
    if url == credentials.externalURL {
      return url.scheme?.lowercased() == "https"
    }
    return false
  }
}

import Foundation

struct HomeAssistantServerAddress: Equatable, Sendable {
  enum ValidationError: Error, Equatable {
    case empty
    case unsupportedScheme
    case missingHost
    case containsCredentials
    case containsQuery
    case containsFragment
    case pointsToEndpoint
  }

  let url: URL

  init(_ input: String) throws(ValidationError) {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      throw .empty
    }

    let completeValue = value.contains("://") ? value : "https://\(value)"
    guard var components = URLComponents(string: completeValue) else {
      throw .missingHost
    }
    guard ["http", "https"].contains(components.scheme?.lowercased()) else {
      throw .unsupportedScheme
    }
    guard components.host?.isEmpty == false else {
      throw .missingHost
    }
    guard components.user == nil, components.password == nil else {
      throw .containsCredentials
    }
    guard components.query == nil else {
      throw .containsQuery
    }
    guard components.fragment == nil else {
      throw .containsFragment
    }
    guard !Self.isEndpointPath(components.path) else {
      throw .pointsToEndpoint
    }

    components.scheme = components.scheme?.lowercased()
    components.path = Self.normalizedPath(components.path)
    guard let url = components.url else {
      throw .missingHost
    }
    self.url = url
  }

  var usesUnencryptedHTTP: Bool {
    url.scheme == "http"
  }

  private static func normalizedPath(_ path: String) -> String {
    guard path != "/" else {
      return ""
    }
    var normalized = path
    while normalized.hasSuffix("/") {
      normalized.removeLast()
    }
    return normalized
  }

  private static func isEndpointPath(_ path: String) -> Bool {
    path.split(separator: "/").contains { component in
      let decoded = String(component).removingPercentEncoding ?? String(component)
      return ["api", "auth"].contains(decoded.lowercased())
    }
  }
}

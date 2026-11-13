import Foundation

/// Access grants belong to an HTTPS authority, independently from Gateway pairing credentials.
struct CloudflareAccessOrigin: Hashable, Codable, Sendable {
  let url: URL

  init(_ url: URL) throws {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(), ["https", "wss"].contains(scheme),
      let host = components.host?.lowercased(), !host.isEmpty,
      components.user == nil, components.password == nil,
      components.query == nil, components.fragment == nil,
      components.port.map({ (1...65535).contains($0) }) ?? true,
      url.absoluteString.utf8.count <= 4096
    else { throw CloudflareAccessError.invalidGateway }
    components.scheme = "https"
    components.host = host
    components.path = ""
    if components.port == 443 { components.port = nil }
    guard let origin = components.url else { throw CloudflareAccessError.invalidGateway }
    self.url = origin
  }

  init(from decoder: Decoder) throws {
    try self.init(decoder.singleValueContainer().decode(URL.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.url)
  }

  func contains(_ url: URL) -> Bool {
    // Resource requests may have queries; credentials and fragments never identify an origin.
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.user == nil, components.password == nil,
      components.fragment == nil
    else { return false }
    components.query = nil
    guard let resource = components.url else { return false }
    return (try? Self(resource)) == self
  }
}

struct CloudflareAccessApplication: Sendable, Equatable {
  let origin: CloudflareAccessOrigin
  let issuer: URL
  let audience: String
}

struct CloudflareAccessSession: Codable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  let origin: CloudflareAccessOrigin
  let issuer: URL
  let audience: String
  let subject: String
  let expiresAt: Date
  private let token: String

  init(application: CloudflareAccessApplication, subject: String, token: String, expiresAt: Date) {
    self.origin = application.origin
    self.issuer = application.issuer
    self.audience = application.audience
    self.subject = subject
    self.token = token
    self.expiresAt = expiresAt
  }

  var description: String {
    "CloudflareAccessSession(<redacted>)"
  }

  var debugDescription: String {
    self.description
  }

  func authorizationHeader(for url: URL, now: Date = Date()) -> String? {
    guard self.origin.contains(url), self.expiresAt > now else { return nil }
    return self.token
  }

  func validate(now: Date = Date()) throws {
    let application = CloudflareAccessApplication(
      origin: self.origin,
      issuer: self.issuer,
      audience: self.audience)
    let claims = try CloudflareAccessJWT.appClaims(self.token, application: application, now: now)
    guard claims.sub == self.subject,
      self.expiresAt.timeIntervalSince1970 == claims.exp
    else { throw CloudflareAccessError.invalidSession }
  }
}

enum CloudflareAccessError: Error {
  case invalidGateway, invalidApplication, connectionFailed, loginFailed, timedOut, invalidSession,
    storageFailed
}

import Foundation
import Security

/// Cloudflare's metadata and app tokens use RS256; verification stays in the platform crypto API.
enum CloudflareAccessJWT {
  struct Claims: Decodable {
    let iss: String
    let aud: Audience
    let type: String
    let sub: String
    let exp: Double
    let nbf: Double?
  }

  struct Audience: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let value = try? container.decode(String.self) {
        self.values = [value]
      } else {
        self.values = try container.decode([String].self)
      }
    }
  }

  private struct Header: Decodable {
    let alg: String
    let kid: String
    let crit: [String]?
  }

  private struct KeySet: Decodable {
    let keys: [CloudflareAccessJWK]
  }

  static func issuer(authDomain: String) throws -> URL {
    let host = authDomain.lowercased()
    let suffix = ".cloudflareaccess.com"
    let team = host.dropLast(suffix.count)
    guard let url = URL(string: "https://\(host)"),
      url.host == host, host.hasSuffix(suffix), (1...63).contains(team.utf8.count),
      team.first != "-", team.last != "-",
      team.utf8.allSatisfy({
        (97...122).contains($0) || (48...57).contains($0) || $0 == 45
      }),
      url.port == nil, url.user == nil, url.password == nil,
      url.path.isEmpty, url.query == nil, url.fragment == nil
    else { throw CloudflareAccessError.invalidApplication }
    return url
  }

  static func application(
    metadata: CloudflareAccessMetadata,
    origin: CloudflareAccessOrigin,
    now: Date = Date()
  ) throws -> CloudflareAccessApplication {
    guard metadata.type == "match", metadata.hostname.lowercased() == origin.url.host,
      !metadata.aud.isEmpty, metadata.aud.utf8.count <= 512,
      metadata.iat > 0, metadata.iat >= now.timeIntervalSince1970 - 86400,
      metadata.iat <= now.timeIntervalSince1970 + 300
    else { throw CloudflareAccessError.invalidApplication }
    return try CloudflareAccessApplication(
      origin: origin,
      issuer: self.issuer(authDomain: metadata.authDomain),
      audience: metadata.aud)
  }

  static func appClaims(
    _ token: String,
    application: CloudflareAccessApplication,
    now: Date = Date()
  ) throws -> Claims {
    let claims = try self.decode(Claims.self, token: token)
    guard let host = application.issuer.host,
      try self.issuer(authDomain: host) == application.issuer,
      claims.iss == application.issuer.absoluteString,
      claims.aud.values.contains(application.audience), claims.aud.values.count <= 16,
      claims.type == "app", !claims.sub.isEmpty, claims.sub.utf8.count <= 512,
      claims.exp.isFinite, claims.exp > now.timeIntervalSince1970,
      claims.nbf.map({ $0.isFinite && $0 <= now.timeIntervalSince1970 }) ?? true
    else { throw CloudflareAccessError.invalidSession }
    return claims
  }

  /// Decoding is only for selecting the constrained issuer or checking an already verified token.
  static func decode<T: Decodable>(_ type: T.Type, token: String) throws -> T {
    let (_, parts) = try self.parts(token)
    return try JSONDecoder().decode(type, from: self.base64URL(parts[1]))
  }

  static func verify(_ token: String, jwks: Data) throws {
    let (header, parts) = try self.parts(token)
    let keySet = try JSONDecoder().decode(KeySet.self, from: jwks)
    guard keySet.keys.count <= 64,
      let key = keySet.keys.first(where: {
        $0.kid == header.kid && $0.kty == "RSA"
          && ($0.alg == nil || $0.alg == "RS256") && ($0.use == nil || $0.use == "sig")
      }),
      let modulus = key.modulus, let exponent = key.exponent
    else { throw CloudflareAccessError.invalidSession }
    let modulusBytes = try self.base64URL(Substring(modulus))
    let exponentBytes = try self.base64URL(Substring(exponent))
    guard (256...1024).contains(modulusBytes.count), (1...8).contains(exponentBytes.count) else {
      throw CloudflareAccessError.invalidSession
    }
    let der = self.der(tag: 0x30, data: self.integer(modulusBytes) + self.integer(exponentBytes))
    guard
      let publicKey = SecKeyCreateWithData(
        der as CFData,
        [
          kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
          kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ] as CFDictionary,
        nil),
      try SecKeyVerifySignature(
        publicKey,
        .rsaSignatureMessagePKCS1v15SHA256,
        Data("\(parts[0]).\(parts[1])".utf8) as CFData,
        self.base64URL(parts[2]) as CFData,
        nil)
    else { throw CloudflareAccessError.invalidSession }
  }

  static func base64URL(_ value: Substring) throws -> Data {
    guard !value.isEmpty,
      value.utf8.allSatisfy({ byte in
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
          || byte == 45 || byte == 95
      })
    else { throw CloudflareAccessError.invalidSession }
    let base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    guard
      let data = Data(
        base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4))
    else {
      throw CloudflareAccessError.invalidSession
    }
    return data
  }

  private static func parts(_ token: String) throws -> (Header, [Substring]) {
    guard token.utf8.count <= 32768 else { throw CloudflareAccessError.invalidSession }
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3,
      let header = try? JSONDecoder().decode(Header.self, from: self.base64URL(parts[0])),
      header.alg == "RS256", !header.kid.isEmpty, header.kid.utf8.count <= 512,
      header.crit?.isEmpty ?? true
    else { throw CloudflareAccessError.invalidSession }
    return (header, parts)
  }

  private static func integer(_ data: Data) -> Data {
    self.der(tag: 0x02, data: (data.first.map { $0 >= 0x80 } ?? false) ? Data([0]) + data : data)
  }

  private static func der(tag: UInt8, data: Data) -> Data {
    let length =
      data.count < 128
      ? [UInt8(data.count)]
      : (data.count < 256
        ? [0x81, UInt8(data.count)] : [0x82, UInt8(data.count >> 8), UInt8(data.count & 255)])
    return Data([tag] + length) + data
  }
}

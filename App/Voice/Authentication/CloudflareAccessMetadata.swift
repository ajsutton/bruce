import Foundation

struct CloudflareAccessMetadata: Decodable {
  let type: String
  let hostname: String
  let authDomain: String
  let aud: String
  let iat: Double

  enum CodingKeys: String, CodingKey {
    case type, hostname, aud, iat
    case authDomain = "auth_domain"
  }
}

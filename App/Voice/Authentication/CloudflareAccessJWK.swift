struct CloudflareAccessJWK: Decodable {
  let kty: String
  let kid: String?
  let alg: String?
  let use: String?
  let modulus: String?
  let exponent: String?

  enum CodingKeys: String, CodingKey {
    case kty, kid, alg, use
    case modulus = "n"
    case exponent = "e"
  }
}

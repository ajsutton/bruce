import Foundation

struct OpenClawAgent: Decodable, Identifiable, Equatable, Sendable {
  struct Identity: Decodable, Equatable, Sendable {
    var name: String?
    var avatarUrl: String?
    var emoji: String?
  }

  let id: String
  var name: String?
  var identity: Identity?

  var displayName: String { name ?? identity?.name ?? id }

  var embeddedAvatar: Data? {
    guard let value = identity?.avatarUrl,
      value.hasPrefix("data:image/"), value.utf8.count <= 8_000_000,
      let separator = value.range(of: ";base64,")
    else { return nil }
    return Data(base64Encoded: String(value[separator.upperBound...]))
  }
}

import CryptoKit
import Foundation

struct OpenClawDeviceIdentity {
  let key: Curve25519.Signing.PrivateKey

  init(credentials: OpenClawCredentialStore) throws {
    if let data = try credentials.load("device-key") {
      key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    } else {
      key = Curve25519.Signing.PrivateKey()
      try credentials.save(key.rawRepresentation, account: "device-key")
    }
  }

  func connectParameters(challenge: OpenClawWireValue) throws -> OpenClawWireValue {
    guard let nonce = challenge["nonce"]?.string,
      let timestamp = challenge["ts"]?.number,
      timestamp >= 0, timestamp < Double(Int64.max), timestamp.rounded() == timestamp
    else { throw OpenClawVoiceError.protocolFailure }
    #if os(iOS)
      let clientID = "openclaw-ios"
      let platform = "ios"
    #else
      let clientID = "openclaw-macos"
      let platform = "macos"
    #endif
    let scopes = ["operator.read", "operator.write"]
    let publicKey = key.publicKey.rawRepresentation
    let id = SHA256.hash(data: publicKey).map { String(format: "%02x", $0) }.joined()
    let message = [
      "v3", id, clientID, "ui", "operator", scopes.joined(separator: ","),
      String(Int64(timestamp)), "", nonce, platform, "",
    ].joined(separator: "|")
    return .object([
      "minProtocol": .number(4), "maxProtocol": .number(4),
      "client": .object([
        "id": .string(clientID), "displayName": .string("Bruce"),
        "version": .string("0.1.0"), "platform": .string(platform), "mode": .string("ui"),
      ]),
      "role": .string("operator"), "scopes": .array(scopes.map { .string($0) }),
      "device": .object([
        "id": .string(id), "publicKey": .string(base64URL(publicKey)),
        "signature": .string(base64URL(try key.signature(for: Data(message.utf8)))),
        "signedAt": .number(timestamp), "nonce": .string(nonce),
      ]),
    ])
  }

  private func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
}

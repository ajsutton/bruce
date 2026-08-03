import Foundation

enum BruceSharedKeychain {
  static let credentialService = "net.symphonious.bruce.shared.home-assistant"
  static let credentialAccount = "credentials"
  static let accessGroupInfoKey = "BruceSharedKeychainAccessGroup"

  static func accessGroup(bundle: Bundle = .main) -> String? {
    bundle.object(forInfoDictionaryKey: accessGroupInfoKey) as? String
  }
}

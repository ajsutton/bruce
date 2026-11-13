import Foundation
import Security

struct OpenClawCredentialStore {
  func load(_ account: String) throws -> Data? {
    var query = query(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw CloudflareAccessError.storageFailed
    }
    return data
  }

  func save(_ data: Data, account: String) throws {
    let attributes: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var item = query(account)
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
        throw CloudflareAccessError.storageFailed
      }
    } else if status != errSecSuccess {
      throw CloudflareAccessError.storageFailed
    }
  }

  private func query(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "net.symphonious.bruce.openclaw",
      kSecAttrAccount as String: account,
    ]
  }
}

import Foundation
import Security

struct WidgetHomeAssistantCredentials: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let instanceID: String?
  let instanceName: String
  let internalURL: URL?
  let externalURL: URL?
  var lastSuccessfulURL: URL
  var accessToken: String
  var refreshToken: String
  let tokenType: String
  var accessTokenExpiresAt: Date
  let clientID: URL

  var sourceIdentifier: String {
    BruceSharedHomeAssistant.sourceIdentifier(
      instanceID: instanceID,
      internalURL: internalURL,
      externalURL: externalURL
    )
  }

  var candidateURLs: [URL] {
    let configuredURLs = [internalURL, externalURL].compactMap(\.self)
    var urls = [
      BruceSharedHomeAssistant.preferredWidgetRoute(for: sourceIdentifier),
      lastSuccessfulURL,
    ].compactMap(\.self).filter(configuredURLs.contains)
    for url in configuredURLs where !urls.contains(url) {
      urls.append(url)
    }
    return urls
  }
}

struct WidgetHomeAssistantCredentialStore {
  func load() throws -> WidgetHomeAssistantCredentials? {
    guard let accessGroup = BruceSharedKeychain.accessGroup() else {
      throw WidgetHomeEnergyError.credentialsUnavailable
    }
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: BruceSharedKeychain.credentialService,
      kSecAttrAccount as String: BruceSharedKeychain.credentialAccount,
      kSecAttrAccessGroup as String: accessGroup,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    #if os(macOS)
      query[kSecUseDataProtectionKeychain as String] = true
    #endif
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess, let data = result as? Data else {
      throw WidgetHomeEnergyError.credentialsUnavailable
    }
    guard
      let credentials = try? JSONDecoder().decode(
        WidgetHomeAssistantCredentials.self,
        from: data
      ),
      credentials.schemaVersion == 1
    else {
      throw WidgetHomeEnergyError.credentialsUnavailable
    }
    return credentials
  }

  @discardableResult
  func save(
    _ credentials: WidgetHomeAssistantCredentials,
    replacing originalCredentials: WidgetHomeAssistantCredentials
  ) throws -> Bool {
    try BruceSharedCredentialLock.withLock {
      guard try load() == originalCredentials,
        let accessGroup = BruceSharedKeychain.accessGroup()
      else { return false }
      var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: BruceSharedKeychain.credentialService,
        kSecAttrAccount as String: BruceSharedKeychain.credentialAccount,
        kSecAttrAccessGroup as String: accessGroup,
        kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
      ]
      #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
      #endif
      let status = SecItemUpdate(
        query as CFDictionary,
        [kSecValueData as String: try JSONEncoder().encode(credentials)] as CFDictionary
      )
      guard status == errSecSuccess else {
        throw WidgetHomeEnergyError.credentialsUnavailable
      }
      return true
    }
  }
}

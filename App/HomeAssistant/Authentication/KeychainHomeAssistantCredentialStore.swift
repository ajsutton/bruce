import Foundation
import Security

struct HomeAssistantKeychainOptions: Equatable, Sendable {
  let isSynchronizable: Bool
  let accessibility: Accessibility

  enum Accessibility: Equatable, Sendable {
    case afterFirstUnlockThisDeviceOnly
  }

  static let credentials = HomeAssistantKeychainOptions(
    isSynchronizable: false,
    accessibility: .afterFirstUnlockThisDeviceOnly
  )
}

protocol HomeAssistantKeychainAccessing: Sendable {
  func load(service: String, account: String) throws -> Data?
  func add(
    _ data: Data,
    service: String,
    account: String,
    options: HomeAssistantKeychainOptions
  ) throws
  func update(
    _ data: Data,
    service: String,
    account: String,
    options: HomeAssistantKeychainOptions
  ) throws
  func delete(service: String, account: String) throws
}

struct SecurityHomeAssistantKeychain: HomeAssistantKeychainAccessing {
  func load(service: String, account: String) throws -> Data? {
    var query = baseQuery(service: service, account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw HomeAssistantCredentialStoreError.keychainFailure(status)
    }
    return result as? Data
  }

  func add(
    _ data: Data,
    service: String,
    account: String,
    options: HomeAssistantKeychainOptions
  ) throws {
    var query = baseQuery(service: service, account: account)
    apply(options, to: &query)
    query[kSecValueData as String] = data
    try check(SecItemAdd(query as CFDictionary, nil))
  }

  func update(
    _ data: Data,
    service: String,
    account: String,
    options: HomeAssistantKeychainOptions
  ) throws {
    var attributes: [String: Any] = [kSecValueData as String: data]
    apply(options, to: &attributes)
    try check(
      SecItemUpdate(
        baseQuery(service: service, account: account) as CFDictionary,
        attributes as CFDictionary
      )
    )
  }

  func delete(service: String, account: String) throws {
    let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw HomeAssistantCredentialStoreError.keychainFailure(status)
    }
  }

  private func baseQuery(service: String, account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
  }

  private func apply(
    _ options: HomeAssistantKeychainOptions,
    to attributes: inout [String: Any]
  ) {
    attributes[kSecAttrSynchronizable as String] =
      options.isSynchronizable ? kCFBooleanTrue : kCFBooleanFalse
    switch options.accessibility {
    case .afterFirstUnlockThisDeviceOnly:
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    }
  }

  private func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else {
      throw HomeAssistantCredentialStoreError.keychainFailure(status)
    }
  }
}

actor KeychainHomeAssistantCredentialStore: HomeAssistantCredentialStoring {
  private let service: String
  private let account: String
  private let keychain: any HomeAssistantKeychainAccessing
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    service: String = "net.symphonious.bruce.home-assistant",
    account: String = "credentials",
    keychain: any HomeAssistantKeychainAccessing = SecurityHomeAssistantKeychain()
  ) {
    self.service = service
    self.account = account
    self.keychain = keychain
  }

  func load() throws -> HomeAssistantCredentials? {
    guard let data = try keychain.load(service: service, account: account) else {
      return nil
    }
    guard let credentials = try? decoder.decode(HomeAssistantCredentials.self, from: data),
      credentials.schemaVersion == HomeAssistantCredentials.currentSchemaVersion
    else {
      throw HomeAssistantCredentialStoreError.corruptData
    }
    return credentials
  }

  func save(_ credentials: HomeAssistantCredentials) throws {
    let data = try encoder.encode(credentials)
    if try keychain.load(service: service, account: account) == nil {
      try keychain.add(
        data,
        service: service,
        account: account,
        options: .credentials
      )
    } else {
      try keychain.update(
        data,
        service: service,
        account: account,
        options: .credentials
      )
    }
  }

  func delete() throws {
    try keychain.delete(service: service, account: account)
  }
}

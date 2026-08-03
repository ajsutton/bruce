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
  func load(service: String, account: String, accessGroup: String?) throws -> Data?
  func add(
    _ data: Data,
    service: String,
    account: String,
    accessGroup: String?,
    options: HomeAssistantKeychainOptions
  ) throws
  func update(
    _ data: Data,
    service: String,
    account: String,
    accessGroup: String?,
    options: HomeAssistantKeychainOptions
  ) throws
  func delete(service: String, account: String, accessGroup: String?) throws
}

struct SecurityHomeAssistantKeychain: HomeAssistantKeychainAccessing {
  func load(service: String, account: String, accessGroup: String?) throws -> Data? {
    var query = baseQuery(service: service, account: account, accessGroup: accessGroup)
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
    accessGroup: String?,
    options: HomeAssistantKeychainOptions
  ) throws {
    var query = baseQuery(service: service, account: account, accessGroup: accessGroup)
    apply(options, to: &query)
    query[kSecValueData as String] = data
    try check(SecItemAdd(query as CFDictionary, nil))
  }

  func update(
    _ data: Data,
    service: String,
    account: String,
    accessGroup: String?,
    options: HomeAssistantKeychainOptions
  ) throws {
    var attributes: [String: Any] = [kSecValueData as String: data]
    apply(options, to: &attributes)
    try check(
      SecItemUpdate(
        baseQuery(service: service, account: account, accessGroup: accessGroup) as CFDictionary,
        attributes as CFDictionary
      )
    )
  }

  func delete(service: String, account: String, accessGroup: String?) throws {
    let status = SecItemDelete(
      baseQuery(service: service, account: account, accessGroup: accessGroup) as CFDictionary
    )
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw HomeAssistantCredentialStoreError.keychainFailure(status)
    }
  }

  private func baseQuery(
    service: String,
    account: String,
    accessGroup: String?
  ) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
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
  private let legacyService: String?
  private let accessGroup: String?
  private let legacyAccessGroup: String?
  private let account: String
  private let keychain: any HomeAssistantKeychainAccessing
  private let connectionDidChange: @Sendable (HomeAssistantCredentials?) -> Void
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private var legacyMigrationAccount: String {
    "\(account).legacy-migration-completed"
  }

  init(
    service: String = "net.symphonious.bruce.home-assistant",
    legacyService: String? = nil,
    accessGroup: String? = nil,
    legacyAccessGroup: String? = nil,
    account: String = "credentials",
    keychain: any HomeAssistantKeychainAccessing = SecurityHomeAssistantKeychain(),
    connectionDidChange: @escaping @Sendable (HomeAssistantCredentials?) -> Void = { _ in }
  ) {
    self.service = service
    self.legacyService = legacyService
    self.accessGroup = accessGroup
    self.legacyAccessGroup = legacyAccessGroup
    self.account = account
    self.keychain = keychain
    self.connectionDidChange = connectionDidChange
  }

  func load() throws -> HomeAssistantCredentials? {
    if let data = try keychain.load(
      service: service,
      account: account,
      accessGroup: accessGroup
    ) {
      let credentials = try decode(data)
      try recordLegacyMigrationIfNeeded()
      connectionDidChange(credentials)
      return credentials
    }
    guard let legacyService,
      try keychain.load(
        service: service,
        account: legacyMigrationAccount,
        accessGroup: accessGroup
      ) == nil,
      let data = try keychain.load(
        service: legacyService,
        account: account,
        accessGroup: legacyAccessGroup
      )
    else {
      return nil
    }
    let credentials = try decode(data)
    try migrateScoped(credentials)
    connectionDidChange(credentials)
    return credentials
  }

  private func decode(_ data: Data) throws -> HomeAssistantCredentials {
    guard let credentials = try? decoder.decode(HomeAssistantCredentials.self, from: data),
      credentials.schemaVersion == HomeAssistantCredentials.currentSchemaVersion
    else {
      throw HomeAssistantCredentialStoreError.corruptData
    }
    return credentials
  }

  func save(_ credentials: HomeAssistantCredentials) throws {
    try recordLegacyMigrationIfNeeded()
    try saveScoped(credentials)
    connectionDidChange(credentials)
  }

  private func saveScoped(_ credentials: HomeAssistantCredentials) throws {
    try withCredentialLock {
      try saveScopedWithoutLock(credentials)
    }
  }

  private func migrateScoped(_ credentials: HomeAssistantCredentials) throws {
    try withCredentialLock {
      try saveScopedWithoutLock(credentials)
      do {
        try recordLegacyMigrationIfNeeded()
      } catch {
        try keychain.delete(service: service, account: account, accessGroup: accessGroup)
        throw error
      }
    }
  }

  private func saveScopedWithoutLock(_ credentials: HomeAssistantCredentials) throws {
    let data = try encoder.encode(credentials)
    if try keychain.load(service: service, account: account, accessGroup: accessGroup) == nil {
      try keychain.add(
        data,
        service: service,
        account: account,
        accessGroup: accessGroup,
        options: .credentials
      )
    } else {
      try keychain.update(
        data,
        service: service,
        account: account,
        accessGroup: accessGroup,
        options: .credentials
      )
    }
  }

  func delete() throws {
    try recordLegacyMigrationIfNeeded()
    try withCredentialLock {
      try keychain.delete(service: service, account: account, accessGroup: accessGroup)
    }
    connectionDidChange(nil)
  }

  private func withCredentialLock(_ operation: () throws -> Void) throws {
    guard accessGroup != nil, keychain is SecurityHomeAssistantKeychain else {
      return try operation()
    }
    try BruceSharedCredentialLock.withLock(operation)
  }

  private func recordLegacyMigrationIfNeeded() throws {
    guard legacyService != nil,
      try keychain.load(
        service: service,
        account: legacyMigrationAccount,
        accessGroup: accessGroup
      ) == nil
    else {
      return
    }
    try keychain.add(
      Data([1]),
      service: service,
      account: legacyMigrationAccount,
      accessGroup: accessGroup,
      options: .credentials
    )
  }
}

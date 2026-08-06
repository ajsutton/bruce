import XCTest

@testable import Bruce

final class HomeAssistantCredentialStoreTests: XCTestCase {
  func testSaveLoadReplaceAndDeleteUseDeviceOnlyNonSynchronizingItem() async throws {
    let keychain = RecordingHomeAssistantKeychain()
    let store = KeychainHomeAssistantCredentialStore(keychain: keychain)
    let first = credentials(accessToken: "first")

    try await store.save(first)

    let loadedFirst = try await store.load()
    XCTAssertEqual(loadedFirst, first)
    XCTAssertEqual(keychain.addedOptions, .credentials)
    XCTAssertFalse(try XCTUnwrap(keychain.addedOptions).isSynchronizable)
    XCTAssertEqual(
      keychain.addedOptions?.accessibility,
      .afterFirstUnlockThisDeviceOnly
    )

    let replacement = credentials(accessToken: "replacement")
    try await store.save(replacement)
    let loadedReplacement = try await store.load()
    XCTAssertEqual(loadedReplacement, replacement)
    XCTAssertEqual(keychain.updateCount, 1)

    try await store.delete()
    let loadedAfterDelete = try await store.load()
    XCTAssertNil(loadedAfterDelete)
  }

  func testCorruptDataIsReportedWithoutDeletingIt() async throws {
    let keychain = RecordingHomeAssistantKeychain()
    keychain.data = Data("not-json".utf8)
    let store = KeychainHomeAssistantCredentialStore(keychain: keychain)

    do {
      _ = try await store.load()
      XCTFail("Expected corrupt data.")
    } catch {
      XCTAssertEqual(error as? HomeAssistantCredentialStoreError, .corruptData)
    }
    XCTAssertNotNil(keychain.data)
    XCTAssertEqual(keychain.deleteCount, 0)
  }

  func testConnectionObserverReceivesReplacementAndDisconnect() async throws {
    let keychain = RecordingHomeAssistantKeychain()
    let observer = CredentialConnectionObserver()
    let store = KeychainHomeAssistantCredentialStore(
      keychain: keychain,
      connectionDidChange: { observer.record($0?.instanceID) }
    )

    try await store.save(credentials(accessToken: "first", instanceID: "first-home"))
    try await store.save(credentials(accessToken: "second", instanceID: "second-home"))
    try await store.delete()

    XCTAssertEqual(observer.instanceIDs, ["first-home", "second-home", nil])
  }

  func testConditionalReplacementPreservesNewerSharedCredentials() async throws {
    let keychain = RecordingHomeAssistantKeychain()
    let store = KeychainHomeAssistantCredentialStore(keychain: keychain)
    let original = credentials(accessToken: "original")
    let newer = credentials(accessToken: "widget-refreshed")
    try await store.save(original)
    try await store.save(newer)

    let didReplace = try await store.replace(
      credentials(accessToken: "app-refreshed"),
      ifCurrentIs: original
    )

    XCTAssertFalse(didReplace)
    let loaded = try await store.load()
    XCTAssertEqual(loaded, newer)
  }

  func testConditionalDeletionPreservesNewerSharedCredentials() async throws {
    let keychain = RecordingHomeAssistantKeychain()
    let store = KeychainHomeAssistantCredentialStore(keychain: keychain)
    let original = credentials(accessToken: "original")
    let newer = credentials(accessToken: "widget-refreshed")
    try await store.save(original)
    try await store.save(newer)

    let didDelete = try await store.replace(nil, ifCurrentIs: original)

    XCTAssertFalse(didDelete)
    let loaded = try await store.load()
    XCTAssertEqual(loaded, newer)
  }

  func testLegacyCredentialMigratesToBundleScopedService() async throws {
    let keychain = RecordingHomeAssistantKeychain()
    let legacyStore = KeychainHomeAssistantCredentialStore(
      service: "net.symphonious.bruce.home-assistant",
      keychain: keychain
    )
    let expected = credentials(accessToken: "legacy")
    try await legacyStore.save(expected)
    let debugStore = KeychainHomeAssistantCredentialStore(
      service: "net.symphonious.bruce.debug.home-assistant",
      legacyService: "net.symphonious.bruce.home-assistant",
      keychain: keychain
    )

    let migrated = try await debugStore.load()

    XCTAssertEqual(migrated, expected)
    XCTAssertNotNil(keychain.data(service: "net.symphonious.bruce.debug.home-assistant"))
  }

  func testDeletingMigratedCredentialDoesNotRestoreItFromLegacyService() async throws {
    let keychain = RecordingHomeAssistantKeychain()
    let legacyStore = KeychainHomeAssistantCredentialStore(
      service: "net.symphonious.bruce.home-assistant",
      keychain: keychain
    )
    try await legacyStore.save(credentials(accessToken: "legacy"))
    let debugStore = KeychainHomeAssistantCredentialStore(
      service: "net.symphonious.bruce.debug.home-assistant",
      legacyService: "net.symphonious.bruce.home-assistant",
      keychain: keychain
    )
    let migrated = try await debugStore.load()
    XCTAssertNotNil(migrated)

    try await debugStore.delete()

    let loadedAfterDelete = try await debugStore.load()
    XCTAssertNil(loadedAfterDelete)
    XCTAssertNotNil(keychain.data(service: "net.symphonious.bruce.home-assistant"))
  }

  func testUnscopedCredentialMigratesIntoTheWidgetAccessGroup() async throws {
    let keychain = RecordingHomeAssistantKeychain()
    let legacyService = "net.symphonious.bruce.debug.home-assistant"
    let sharedService = "net.symphonious.bruce.shared.home-assistant"
    let accessGroup = "TEAM.net.symphonious.bruce.debug.shared"
    let legacyStore = KeychainHomeAssistantCredentialStore(
      service: legacyService,
      keychain: keychain
    )
    let expected = credentials(accessToken: "shared")
    try await legacyStore.save(expected)
    let sharedStore = KeychainHomeAssistantCredentialStore(
      service: sharedService,
      legacyService: legacyService,
      accessGroup: accessGroup,
      keychain: keychain
    )

    let migrated = try await sharedStore.load()

    XCTAssertEqual(migrated, expected)
    XCTAssertNotNil(
      keychain.data(service: sharedService, accessGroup: accessGroup)
    )
  }

  private func credentials(
    accessToken: String,
    instanceID: String = "instance"
  ) -> HomeAssistantCredentials {
    let localURL = URL(string: "http://home.local:8123") ?? URL(fileURLWithPath: "/")
    return HomeAssistantCredentials(
      instanceID: instanceID,
      instanceName: "Home",
      internalURL: localURL,
      externalURL: URL(string: "https://home.example.com"),
      lastSuccessfulURL: localURL,
      accessToken: accessToken,
      refreshToken: "refresh-value",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 1_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

private final class CredentialConnectionObserver: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String?] = []

  var instanceIDs: [String?] { lock.withLock { values } }

  func record(_ instanceID: String?) {
    lock.withLock { values.append(instanceID) }
  }
}

private final class RecordingHomeAssistantKeychain:
  HomeAssistantKeychainAccessing, @unchecked Sendable
{
  private let lock = NSLock()
  private var storedDataByKey: [String: Data] = [:]
  private(set) var addedOptions: HomeAssistantKeychainOptions?
  private(set) var updateCount = 0
  private(set) var deleteCount = 0

  var data: Data? {
    get { data(service: "net.symphonious.bruce.home-assistant") }
    set {
      lock.withLock {
        storedDataByKey[
          key(service: "net.symphonious.bruce.home-assistant", account: "credentials")
        ] = newValue
      }
    }
  }

  func data(
    service: String,
    account: String = "credentials",
    accessGroup: String? = nil
  ) -> Data? {
    lock.withLock {
      storedDataByKey[key(service: service, account: account, accessGroup: accessGroup)]
    }
  }

  func load(service: String, account: String, accessGroup: String?) throws -> Data? {
    data(service: service, account: account, accessGroup: accessGroup)
  }

  func add(
    _ data: Data,
    service: String,
    account: String,
    accessGroup: String?,
    options: HomeAssistantKeychainOptions
  ) throws {
    lock.withLock {
      storedDataByKey[key(service: service, account: account, accessGroup: accessGroup)] = data
      addedOptions = options
    }
  }

  func update(
    _ data: Data,
    service: String,
    account: String,
    accessGroup: String?,
    options: HomeAssistantKeychainOptions
  ) throws {
    lock.withLock {
      storedDataByKey[key(service: service, account: account, accessGroup: accessGroup)] = data
      updateCount += 1
    }
  }

  func delete(service: String, account: String, accessGroup: String?) throws {
    lock.withLock {
      storedDataByKey[key(service: service, account: account, accessGroup: accessGroup)] = nil
      deleteCount += 1
    }
  }

  private func key(service: String, account: String, accessGroup: String? = nil) -> String {
    "\(accessGroup ?? "unscoped")|\(service)|\(account)"
  }
}

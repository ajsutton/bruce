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

  private func credentials(accessToken: String) -> HomeAssistantCredentials {
    let localURL = URL(string: "http://home.local:8123") ?? URL(fileURLWithPath: "/")
    return HomeAssistantCredentials(
      instanceID: "instance",
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

  func data(service: String, account: String = "credentials") -> Data? {
    lock.withLock { storedDataByKey[key(service: service, account: account)] }
  }

  func load(service: String, account: String) throws -> Data? {
    data(service: service, account: account)
  }

  func add(
    _ data: Data,
    service: String,
    account: String,
    options: HomeAssistantKeychainOptions
  ) throws {
    lock.withLock {
      storedDataByKey[key(service: service, account: account)] = data
      addedOptions = options
    }
  }

  func update(
    _ data: Data,
    service: String,
    account: String,
    options: HomeAssistantKeychainOptions
  ) throws {
    lock.withLock {
      storedDataByKey[key(service: service, account: account)] = data
      updateCount += 1
    }
  }

  func delete(service: String, account: String) throws {
    lock.withLock {
      storedDataByKey[key(service: service, account: account)] = nil
      deleteCount += 1
    }
  }

  private func key(service: String, account: String) -> String {
    "\(service)|\(account)"
  }
}

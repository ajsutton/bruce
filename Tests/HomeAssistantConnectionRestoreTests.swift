import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantConnectionRestoreTests: XCTestCase {
  func testConcurrentConsumersWaitForTheSameSavedConnectionRestore() async throws {
    let connection = SuspendedSavedConnection()
    let controller = HomeAssistantConnectionController(connection: connection)
    let first = Task { await controller.restoreSavedConnection() }
    await fulfillment(of: [connection.started], timeout: 1)
    let secondStarted = expectation(description: "Second consumer entered restore")
    let second = Task {
      secondStarted.fulfill()
      await controller.restoreSavedConnection()
      return controller.connectedCredentials
    }
    await fulfillment(of: [secondStarted], timeout: 1)
    let credentials = SessionFixture().credentials()

    connection.finish(with: credentials)
    _ = await first.value
    let secondCredentials = await second.value

    XCTAssertEqual(secondCredentials, credentials)
    XCTAssertEqual(connection.restoreCount, 1)
  }

  func testChangingServerReleasesRestoreWaitersAndRejectsLateCredentials() async throws {
    let connection = SuspendedSavedConnection()
    let controller = HomeAssistantConnectionController(connection: connection)
    let finished = expectation(description: "Invalidated restore consumer returned")
    let restore = Task {
      await controller.restoreSavedConnection()
      finished.fulfill()
    }
    await fulfillment(of: [connection.started], timeout: 1)

    controller.changeServer()

    let completion = await XCTWaiter.fulfillment(of: [finished], timeout: 1)
    XCTAssertEqual(completion, .completed)
    connection.finish(with: SessionFixture().credentials())
    await fulfillment(of: [connection.returned], timeout: 1)
    await restore.value
    XCTAssertNil(controller.connectedCredentials)
    guard case .introduction = controller.step else {
      return XCTFail("The stale credential restore must not replace the changed-server state.")
    }
  }

  func testChangingServerDuringRestorePreventsALateSiriChargerWrite() async throws {
    let connection = SuspendedSavedConnection()
    let store = HomeAssistantSetupStore(
      discovery: EmptyTemperatureDiscovery(), connection: connection)
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let client = HomeAssistantAPIClient(session: session)
    let service = BruceSiriService(
      energy: client, charger: client,
      prepare: {
        try await store.prepareSavedConnection()
      })
    let finished = expectation(description: "Invalidated Siri command returned")
    let command = Task {
      defer { finished.fulfill() }
      do {
        try await service.setChargerMode(.smart)
        XCTFail("An invalidated command must not succeed.")
      } catch BruceSiriError.modeNotConfirmed {
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
    }
    await fulfillment(of: [connection.started], timeout: 1)

    store.changeServer()

    let completion = await XCTWaiter.fulfillment(of: [finished], timeout: 1)
    XCTAssertEqual(completion, .completed)
    connection.finish(with: fixture.credentials())
    await fulfillment(of: [connection.returned], timeout: 1)
    await command.value
    do {
      try await service.setChargerMode(.smart)
      XCTFail("A new Siri command must not use the previous server during setup.")
    } catch BruceSiriError.signInRequired {
    }
    do {
      _ = try await service.solarGeneration()
      XCTFail("A new Siri query must not use the previous server during setup.")
    } catch BruceSiriError.signInRequired {
    }
    XCTAssertTrue(
      fixture.apiLoader.requests.isEmpty, "No old-server request may start after invalidation.")
  }

  func testTemporaryRestoreFailureRemainsRetryableAndIsNotReportedAsMissingCredentials()
    async throws
  {
    let connection = RetryingSavedConnection()
    let store = HomeAssistantSetupStore(
      discovery: EmptyTemperatureDiscovery(), connection: connection)

    do {
      try await store.prepareSavedConnection()
      XCTFail("Expected the transient Keychain error.")
    } catch HomeAssistantCredentialStoreError.keychainFailure(-25308) {
    }

    try await store.prepareSavedConnection()

    guard case .connected(let credentials) = store.step else {
      return XCTFail("Expected saved credentials to be restored on retry.")
    }
    XCTAssertEqual(credentials, connection.credentials)
    XCTAssertEqual(connection.restoreCount, 2)
  }

}

@MainActor
private final class SuspendedSavedConnection: HomeAssistantConnecting {
  let started = XCTestExpectation(description: "Credential restore started")
  let returned = XCTestExpectation(description: "Credential restore returned")
  private var continuation: CheckedContinuation<HomeAssistantCredentials?, Never>?
  private(set) var restoreCount = 0

  func restore() async throws -> HomeAssistantCredentials? {
    restoreCount += 1
    defer { returned.fulfill() }
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
      started.fulfill()
    }
  }

  func finish(with credentials: HomeAssistantCredentials) {
    continuation?.resume(returning: credentials)
    continuation = nil
  }

  func authenticate(to candidate: HomeAssistantConnectionCandidate) async throws
    -> HomeAssistantCredentials
  {
    throw HomeAssistantAPIError.noCredentials
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    throw HomeAssistantAPIError.noCredentials
  }

  func disconnect() async throws {}
  func cancel() {}
}

@MainActor
private final class RetryingSavedConnection: HomeAssistantConnecting {
  let credentials = SessionFixture().credentials()
  private(set) var restoreCount = 0

  func restore() async throws -> HomeAssistantCredentials? {
    restoreCount += 1
    if restoreCount == 1 { throw HomeAssistantCredentialStoreError.keychainFailure(-25308) }
    return credentials
  }

  func authenticate(to candidate: HomeAssistantConnectionCandidate) async throws
    -> HomeAssistantCredentials
  {
    throw HomeAssistantAPIError.noCredentials
  }

  func testConnection() async throws -> HomeAssistantCredentials { credentials }
  func disconnect() async throws {}
  func cancel() {}
}

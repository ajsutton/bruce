import XCTest

@testable import Bruce

extension HASessionRejectionPersistenceTests {
  func testCancelledCallerStillStartsCredentialRejection() async throws {
    let fixture = SessionFixture()
    let store = BlockingCredentialRejectionStore()
    let session = makeSession(
      fixture: fixture,
      store: store,
      refreshLoader: BlockingHomeAssistantLoader(),
      refreshWaiterRegistered: { _ in },
      rejectionWaiterRegistered: { _ in }
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))
    await store.blockNextReplacement()
    let cancelled = TaskResultProbe<Void>(description: "Cancelled rejection waiter completed")
    let cancelledTask = rejectionTask(session: session, probe: cancelled)

    cancelledTask.cancel()
    await fulfillment(of: [store.replacementStarted], timeout: 1)
    let observer = TaskResultProbe<Void>(description: "Rejection observer completed")
    _ = rejectionTask(session: session, probe: observer)
    await store.completeReplacement()

    await assertCancelled(cancelled)
    await assertReauthenticationRequired(observer)
    let snapshot = await session.connectionSnapshot()
    XCTAssertEqual(snapshot.availability, .rejected)
  }

  func testFailedInstallAfterRejectionRemainsRejected() async throws {
    let fixture = SessionFixture()
    let store = BlockingCredentialRejectionStore()
    let replacementJoined = expectation(description: "Install waits for rejection")
    let session = makeSession(
      fixture: fixture,
      store: store,
      refreshLoader: BlockingHomeAssistantLoader(),
      refreshWaiterRegistered: { _ in },
      rejectionWaiterRegistered: expectation(for: replacementJoined)
    )
    let credentials = fixture.credentials(expiresAt: fixture.past)
    try await session.install(credentials)
    await store.blockNextReplacement()
    let rejection = TaskResultProbe<Void>(description: "Rejection completed")
    _ = rejectionTask(session: session, probe: rejection)
    await fulfillment(of: [store.replacementStarted], timeout: 1)
    await store.failNextSave()
    var replacement = credentials
    replacement.accessToken = "replacement"
    let install = TaskResultProbe<Void>(description: "Install completed")
    _ = installTask(session: session, credentials: replacement, probe: install)
    await fulfillment(of: [replacementJoined], timeout: 1)

    await store.completeReplacement()

    await assertReauthenticationRequired(rejection)
    await assertStoreFailure(install)
    let snapshot = await session.connectionSnapshot()
    XCTAssertEqual(snapshot.availability, .rejected)
  }

  func testRestoreAfterRejectionRemainsRejected() async throws {
    let fixture = SessionFixture()
    let store = BlockingCredentialRejectionStore()
    let replacementJoined = expectation(description: "Restore waits for rejection")
    let session = makeSession(
      fixture: fixture,
      store: store,
      refreshLoader: BlockingHomeAssistantLoader(),
      refreshWaiterRegistered: { _ in },
      rejectionWaiterRegistered: expectation(for: replacementJoined)
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))
    await store.blockNextReplacement()
    let rejection = TaskResultProbe<Void>(description: "Rejection completed")
    _ = rejectionTask(session: session, probe: rejection)
    await fulfillment(of: [store.replacementStarted], timeout: 1)
    let restore = TaskResultProbe<Bool>(description: "Restore completed")
    _ = restoreTask(session: session, probe: restore)
    await fulfillment(of: [replacementJoined], timeout: 1)

    await store.completeReplacement()

    await assertReauthenticationRequired(rejection)
    await assertReauthenticationRequired(restore)
    let snapshot = await session.connectionSnapshot()
    XCTAssertEqual(snapshot.availability, .rejected)
  }

  func testExternallyDeletedRejectedCredentialsRemainRejected() async throws {
    let fixture = SessionFixture()
    let store = ExternallyDeletedCredentialStore()
    let session = makeSession(
      fixture: fixture,
      store: store,
      refreshLoader: BlockingHomeAssistantLoader(),
      refreshWaiterRegistered: { _ in },
      rejectionWaiterRegistered: { _ in }
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))
    await store.deleteExternally()
    let rejection = TaskResultProbe<Void>(description: "Rejection completed")
    _ = rejectionTask(session: session, probe: rejection)

    await assertReauthenticationRequired(rejection)
    let snapshot = await session.connectionSnapshot()
    XCTAssertEqual(snapshot.availability, .rejected)
  }

  func assertStoreFailure<Value>(_ probe: TaskResultProbe<Value>) async {
    await fulfillment(of: [probe.completed], timeout: 1)
    guard let result = await probe.recordedResult() else { return }
    guard case .failure(let error) = result else {
      XCTFail("Expected store failure.")
      return
    }
    if !(error is RejectionPersistenceTestError) {
      XCTFail("Unexpected error: \(error)")
    }
  }
}

actor TaskResultProbe<Value: Sendable> {
  nonisolated let completed: XCTestExpectation
  private var result: Result<Value, any Error>?

  init(description: String) {
    completed = XCTestExpectation(description: description)
  }

  func record(_ result: Result<Value, any Error>) {
    self.result = result
    completed.fulfill()
  }

  func recordedResult() -> Result<Value, any Error>? { result }
}

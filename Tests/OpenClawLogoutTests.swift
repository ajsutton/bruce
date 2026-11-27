import Combine
import XCTest

@testable import Bruce

@MainActor
final class OpenClawLogoutTests: XCTestCase {
  private let agent = OpenClawAgent(id: "house", name: "Bruce — House", identity: nil)

  func testLogoutEndsAudioAndRemovesTheCachedAgentSelection() async throws {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let audio = VoiceAudioDouble()
    let system = VoiceSystemDouble()
    let store = OpenClawVoiceStore(
      client: client, systemCall: system, makeAudio: { audio })
    await prepare(store)
    await transition(store, to: .connected) { store.start(self.agent) }

    try await store.logOut()

    XCTAssertTrue(audio.isClosed)
    XCTAssertFalse(store.hasCall)
    XCTAssertTrue(store.agents.isEmpty)
    XCTAssertNil(store.agent)
    XCTAssertNil(store.browser)
    XCTAssertEqual(store.phase, .idle)
    XCTAssertEqual(client.logoutCount, 1)
    client.roster = []
    await prepare(store)
    XCTAssertEqual(client.rosterCount, 2)
    XCTAssertTrue(store.agents.isEmpty)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  func testLogoutCancelsSignInWithoutAcceptingItsLateResult() async throws {
    let client = VoiceClientDouble()
    client.signInURL = try XCTUnwrap(URL(string: "https://example.invalid/login"))
    client.roster = [agent]
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    await transition(store, to: .signingIn) { store.prepare() }
    let browser = try XCTUnwrap(store.browser)

    try await store.logOut()
    store.continueSignIn(browserID: browser.id)

    XCTAssertEqual(store.phase, .idle)
    XCTAssertNil(store.browser)
    XCTAssertTrue(store.agents.isEmpty)
    XCTAssertEqual(client.logoutCount, 1)
  }

  func testLogoutWaitsForCancelledRosterBeforeDeletingCredentials() async throws {
    let client = VoiceClientDouble()
    client.roster = [agent]
    client.blocksRoster = true
    let started = expectation(description: "Roster started")
    client.onRoster = { started.fulfill() }
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    store.prepare()
    await fulfillment(of: [started], timeout: 3)
    let logout = Task { try await store.logOut() }
    defer { logout.cancel() }
    await waitForLogout(store)

    XCTAssertEqual(client.logoutCount, 0)
    client.finishRoster?()
    try await logout.value

    XCTAssertTrue(store.agents.isEmpty)
    XCTAssertEqual(store.phase, .idle)
    XCTAssertEqual(client.logoutCount, 1)
  }

  func testVisiblePickersCannotRestartVoiceDuringLogout() async throws {
    let client = VoiceClientDouble()
    client.roster = [agent]
    client.blocksClose = true
    let closing = expectation(description: "Client closing")
    client.onClose = { closing.fulfill() }
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    await prepare(store)
    let logout = Task { try await store.logOut() }
    defer { logout.cancel() }
    await fulfillment(of: [closing], timeout: 3)

    store.presentPicker(id: UUID())
    store.prepare()
    client.onDisconnect?()
    client.finishClose?()
    try await logout.value

    XCTAssertEqual(store.phase, .idle)
    XCTAssertEqual(client.rosterCount, 1)
    XCTAssertEqual(client.logoutCount, 1)
    XCTAssertFalse(store.isLoggingOut)
  }

  func testLogoutDuringHangupDoesNotReturnToTheVisiblePicker() async throws {
    let client = VoiceClientDouble()
    client.roster = [agent]
    client.blocksClose = true
    let closing = expectation(description: "Existing hangup closing")
    client.onClose = { closing.fulfill() }
    let store = OpenClawVoiceStore(
      client: client, systemCall: VoiceSystemDouble(), makeAudio: { VoiceAudioDouble() })
    store.presentPicker(id: UUID())
    await prepare(store)
    await transition(store, to: .connected) { store.start(self.agent) }
    store.end()
    await fulfillment(of: [closing], timeout: 3)
    let logout = Task { try await store.logOut() }
    defer { logout.cancel() }
    await waitForLogout(store)

    client.finishClose?()
    try await logout.value

    XCTAssertEqual(store.phase, .idle)
    XCTAssertEqual(client.logoutCount, 1)
    XCTAssertEqual(client.rosterCount, 1)
    XCTAssertTrue(store.agents.isEmpty)
  }

  func testConcurrentLogoutsWaitForTheSameCredentialDeletionFailure() async {
    let client = VoiceClientDouble()
    client.blocksClose = true
    client.failsLogout = true
    let closing = expectation(description: "Client closing for logout")
    client.onClose = { closing.fulfill() }
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    var completionCount = 0
    let first = Task {
      defer { completionCount += 1 }
      return await logoutRejectsCredentialFailure(store)
    }
    defer { first.cancel() }
    await fulfillment(of: [closing], timeout: 3)
    let secondStarted = expectation(description: "Concurrent logout entered")
    let second = Task {
      defer { completionCount += 1 }
      secondStarted.fulfill()
      return await logoutRejectsCredentialFailure(store)
    }
    defer { second.cancel() }
    await fulfillment(of: [secondStarted], timeout: 3)

    XCTAssertEqual(completionCount, 0)
    XCTAssertEqual(client.logoutCount, 0)
    client.finishClose?()
    let firstRejected = await first.value
    let secondRejected = await second.value

    XCTAssertTrue(firstRejected)
    XCTAssertTrue(secondRejected)
    XCTAssertEqual(client.logoutCount, 1)
  }

  private func logoutRejectsCredentialFailure(_ store: OpenClawVoiceStore) async -> Bool {
    do {
      try await store.logOut()
      return false
    } catch CloudflareAccessError.storageFailed {
      return true
    } catch {
      XCTFail("Unexpected logout error: \(error)")
      return false
    }
  }

  func testCredentialRemovalFailureIsReportedAndCanBeRetried() async throws {
    let client = VoiceClientDouble()
    client.failsLogout = true
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())

    do {
      try await store.logOut()
      XCTFail("Credential deletion failure must reach the settings screen.")
    } catch CloudflareAccessError.storageFailed {
    }
    XCTAssertFalse(store.isLoggingOut)
    client.failsLogout = false
    try await store.logOut()

    XCTAssertEqual(client.logoutCount, 2)
    XCTAssertEqual(store.phase, .idle)
  }

  private func prepare(_ store: OpenClawVoiceStore) async {
    await transition(store, to: .choosing) { store.prepare() }
  }

  private func waitForLogout(_ store: OpenClawVoiceStore) async {
    let started = expectation(description: "Logout started")
    let subscription = store.$isLoggingOut.first(where: { $0 }).sink { _ in started.fulfill() }
    await fulfillment(of: [started], timeout: 3)
    withExtendedLifetime(subscription) {}
  }

  private func transition(
    _ store: OpenClawVoiceStore, to phase: OpenClawVoiceStore.Phase, action: () -> Void
  ) async {
    let reached = expectation(description: "Voice reaches \(phase)")
    let subscription = store.$phase.first(where: { $0 == phase }).sink { _ in reached.fulfill() }
    action()
    await fulfillment(of: [reached], timeout: 3)
    withExtendedLifetime(subscription) {}
  }
}

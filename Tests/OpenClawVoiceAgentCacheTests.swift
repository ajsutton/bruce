import Combine
import XCTest

@testable import Bruce

@MainActor
final class OpenClawVoiceAgentCacheTests: XCTestCase {
  func testReopeningThePickerUsesMemoryAndANewStoreLoadsFreshAgents() async {
    let client = VoiceClientDouble()
    client.roster = [OpenClawAgent(id: "house", name: "Bruce — House", identity: nil)]
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
    client.roster = [OpenClawAgent(id: "family", name: "Bruce — Family", identity: nil)]
    store.prepare()
    XCTAssertEqual(store.phase, .choosing)
    XCTAssertEqual(store.agents.map(\.id), ["house"])
    XCTAssertEqual(client.rosterCount, 1)
    XCTAssertEqual(client.connectCount, 0)
    await transition(store, to: .choosing) { store.refreshAgents() }
    XCTAssertEqual(store.agents.map(\.id), ["family"])
    XCTAssertEqual(client.rosterCount, 2)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
    let freshStore = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    await transition(freshStore, to: .choosing) { freshStore.prepare() }
    XCTAssertEqual(freshStore.agents.map(\.id), ["family"])
    XCTAssertEqual(client.rosterCount, 3)
    await transition(freshStore, to: .idle) { freshStore.end(returnToPicker: false) }
  }

  func testCachedPickerCanReauthenticateBeforeStartingTheSystemCall() async throws {
    let client = VoiceClientDouble()
    let agent = OpenClawAgent(id: "house", name: "Bruce — House", identity: nil)
    client.roster = [agent]
    let system = VoiceSystemDouble()
    let store = OpenClawVoiceStore(
      client: client, systemCall: system, makeAudio: { VoiceAudioDouble() })
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
    store.prepare()
    client.connectSignInURL = try XCTUnwrap(URL(string: "https://example.invalid/sign-in"))
    await transition(store, to: .signingIn) { store.start(agent) }
    XCTAssertTrue(system.agents.isEmpty)
    XCTAssertTrue(client.startedAgents.isEmpty)
    let browser = try XCTUnwrap(store.browser)
    await transition(store, to: .connected) { store.continueSignIn(browserID: browser.id) }
    XCTAssertEqual(client.rosterCount, 1)
    XCTAssertEqual(client.connectCount, 1)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  func testAFailedCallInvalidatesTheCacheForRetry() async {
    let client = VoiceClientDouble()
    let agent = OpenClawAgent(id: "house", name: "Bruce — House", identity: nil)
    client.roster = [agent]
    let system = VoiceSystemDouble()
    system.rejectsStart = true
    let store = OpenClawVoiceStore(
      client: client, systemCall: system, makeAudio: { VoiceAudioDouble() })
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .failed) { store.start(agent) }
    client.roster = []
    await transition(store, to: .choosing) { store.prepare() }
    XCTAssertTrue(store.agents.isEmpty)
    XCTAssertEqual(client.rosterCount, 2)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
    store.prepare()
    XCTAssertEqual(store.phase, .choosing)
    XCTAssertEqual(client.rosterCount, 2)
    client.roster = [agent]
    await transition(store, to: .choosing) { store.refreshAgents() }
    XCTAssertEqual(store.agents.map(\.id), [agent.id])
    XCTAssertEqual(client.rosterCount, 3)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  func testInteractiveSignInDoesNotStartTheCallTimeout() async throws {
    let client = VoiceClientDouble()
    let agent = OpenClawAgent(id: "house", name: "Bruce — House", identity: nil)
    client.roster = [agent]
    client.connectSignInURL = try XCTUnwrap(URL(string: "https://example.invalid/sign-in"))
    var deadlines = 0
    let store = OpenClawVoiceStore(
      client: client, systemCall: VoiceSystemDouble(), makeAudio: { VoiceAudioDouble() },
      waitForConnectionTimeout: { _ in
        deadlines += 1
        throw CancellationError()
      })
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .signingIn) { store.start(agent) }
    XCTAssertEqual(deadlines, 0)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
    XCTAssertEqual(deadlines, 0)
    XCTAssertTrue(client.startedAgents.isEmpty)
  }

  func testLateFailureDuringNormalHangupPreservesCachedAgents() async {
    let client = VoiceClientDouble()
    let agent = OpenClawAgent(id: "house", name: "Bruce — House", identity: nil)
    client.roster = [agent]
    let store = OpenClawVoiceStore(
      client: client, systemCall: VoiceSystemDouble(), makeAudio: { VoiceAudioDouble() })
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(agent) }
    await transition(store, to: .idle) {
      store.end(returnToPicker: false)
      client.onDisconnect?()
    }
    store.prepare()
    XCTAssertEqual(store.phase, .choosing)
    XCTAssertEqual(client.rosterCount, 1)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  func testCancellingRefreshRejectsTheLateRoster() async {
    let client = VoiceClientDouble()
    client.roster = [OpenClawAgent(id: "house", name: "Bruce — House", identity: nil)]
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    await transition(store, to: .choosing) { store.prepare() }
    client.blocksRoster = true
    let loading = expectation(description: "Refreshing agents")
    client.onRoster = { loading.fulfill() }
    store.refreshAgents()
    await fulfillment(of: [loading], timeout: 3)
    await transition(store, to: .idle) {
      store.end(returnToPicker: false)
      client.finishRoster?()
    }
    XCTAssertTrue(store.agents.isEmpty)
    XCTAssertEqual(store.phase, .idle)
  }

  func testExplicitRefreshFailureIsShownAndCanBeRetried() async {
    let client = VoiceClientDouble()
    client.roster = [OpenClawAgent(id: "house", name: "Bruce — House", identity: nil)]
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    await transition(store, to: .choosing) { store.prepare() }
    client.failsRoster = true
    await transition(store, to: .failed) { store.refreshAgents() }
    XCTAssertNotNil(store.problem)
    XCTAssertTrue(store.agents.isEmpty)
    client.failsRoster = false
    await transition(store, to: .choosing) { store.prepare() }
    XCTAssertEqual(client.rosterCount, 3)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  private func transition(
    _ store: OpenClawVoiceStore, to phase: OpenClawVoiceStore.Phase, action: () -> Void
  ) async {
    let reached = expectation(description: "Voice reaches \(phase)")
    let subscription = store.$phase.dropFirst().first(where: { $0 == phase }).sink { _ in
      reached.fulfill()
    }
    action()
    await fulfillment(of: [reached], timeout: 3)
    withExtendedLifetime(subscription) {}
  }
}

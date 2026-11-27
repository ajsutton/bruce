import Combine
import XCTest

@testable import Bruce

@MainActor
final class DemoVoiceTests: XCTestCase {
  func testDemoAgentsLoadWithoutRequestingSignIn() async throws {
    let client = DemoVoiceClient()
    let agents = try await client.agents { _, _ in XCTFail("Demo must not sign in") }
    XCTAssertEqual(agents.map(\.id), ["house", "family"])
    try await client.connect { _, _ in XCTFail("Demo calls must not sign in") }
  }

  func testDemoCallsSupportMuteEndAndAnotherAgent() async throws {
    let audio = VoiceAudioDouble()
    let store = OpenClawVoiceStore(
      client: DemoVoiceClient(), systemCall: DemoSystemCall(), makeAudio: { audio })
    await transition(store, to: .choosing) { store.prepare() }
    let agents = store.agents
    guard agents.count == 2 else { return XCTFail("Expected both demo agents") }
    await transition(store, to: .connected) { store.start(agents[0]) }
    store.toggleMute()
    XCTAssertTrue(store.isMuted)
    XCTAssertEqual(audio.mutedValues, [true])
    store.toggleMute()
    XCTAssertFalse(store.isMuted)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
    XCTAssertTrue(audio.isClosed)
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(agents[1]) }
    XCTAssertEqual(store.agent?.id, "family")
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  func testEndingWhileDemoConnectsDoesNotLeaveAnActiveCall() async {
    let store = OpenClawVoiceStore(
      client: DemoVoiceClient(), systemCall: DemoSystemCall(),
      makeAudio: { VoiceAudioDouble() })
    await transition(store, to: .choosing) { store.prepare() }
    guard let agent = store.agents.first else { return XCTFail("Missing demo agent") }
    await transition(store, to: .idle) {
      store.start(agent)
      store.end(returnToPicker: false)
    }
    XCTAssertFalse(store.hasCall)
  }

  private func transition(
    _ store: OpenClawVoiceStore, to phase: OpenClawVoiceStore.Phase, action: () -> Void
  ) async {
    let reached = expectation(description: "Demo voice reaches \(phase)")
    let subscription = store.$phase.first(where: { $0 == phase }).sink { _ in reached.fulfill() }
    action()
    await fulfillment(of: [reached], timeout: 3)
    withExtendedLifetime(subscription) {}
  }
}

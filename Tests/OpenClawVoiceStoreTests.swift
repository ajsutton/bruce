import Combine
import XCTest

@testable import Bruce

@MainActor
final class OpenClawVoiceStoreTests: XCTestCase {
  private let agent = OpenClawAgent(id: "family", name: "Bruce — Family", identity: nil)

  func testPickerUsesAccessibleAgentsAndTheirConfiguredNames() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    await transition(store, to: .choosing) { store.prepare() }
    XCTAssertEqual(store.agents.map(\.displayName), ["Bruce — Family"])
    XCTAssertTrue(client.startedAgents.isEmpty)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  func testStartingUsesTheSelectedAgentAndMutesTheActiveAudio() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let audio = VoiceAudioDouble()
    let store = OpenClawVoiceStore(
      client: client, systemCall: VoiceSystemDouble(), makeAudio: { audio })
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    XCTAssertEqual(client.startedAgents, ["family"])
    XCTAssertEqual(store.agent?.displayName, "Bruce — Family")
    store.toggleMute()
    XCTAssertTrue(store.isMuted)
    XCTAssertEqual(audio.mutedValues, [true])
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
    XCTAssertTrue(audio.isClosed)
    XCTAssertEqual(client.closeCount, 1)
  }

  func testStartingAgainCreatesAnotherConversationInsteadOfResuming() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let store = OpenClawVoiceStore(
      client: client, systemCall: VoiceSystemDouble(), makeAudio: { VoiceAudioDouble() })
    for _ in 0..<2 {
      await transition(store, to: .choosing) { store.prepare() }
      await transition(store, to: .connected) { store.start(self.agent) }
      await transition(store, to: .idle) { store.end(returnToPicker: false) }
    }
    XCTAssertEqual(client.startedAgents, ["family", "family"])
    XCTAssertEqual(client.closeCount, 2)
  }

  func testEndingDuringMicrophonePermissionNeverStartsRemoteVoice() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let audio = VoiceAudioDouble()
    audio.blocksOffer = true
    let offered = expectation(description: "Microphone permission pending")
    audio.onOffer = { offered.fulfill() }
    let store = OpenClawVoiceStore(
      client: client, systemCall: VoiceSystemDouble(), makeAudio: { audio })
    await transition(store, to: .choosing) { store.prepare() }
    store.start(agent)
    await fulfillment(of: [offered], timeout: 2)
    await transition(store, to: .idle) {
      store.end(returnToPicker: false)
    }
    XCTAssertTrue(client.startedAgents.isEmpty)
    XCTAssertTrue(audio.isClosed)
    XCTAssertFalse(store.hasCall)
  }

  func testAConnectionFailureClosesAudioAndShowsRetry() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let audio = VoiceAudioDouble()
    let store = OpenClawVoiceStore(
      client: client, systemCall: VoiceSystemDouble(), makeAudio: { audio })
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    await transition(store, to: .failed) { client.onDisconnect?() }
    XCTAssertTrue(audio.isClosed)
    XCTAssertFalse(store.hasCall)
    XCTAssertNotNil(store.problem)
  }

  func testBriefWiFiInterruptionCanReconnectTheSameCall() async {
    let system = VoiceSystemDouble()
    let client = VoiceClientDouble()
    client.roster = [agent]
    let audio = VoiceAudioDouble()
    let store = OpenClawVoiceStore(
      client: client, systemCall: system, makeAudio: { audio })
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    audio.onConnectionChange?(.disconnected)
    XCTAssertEqual(store.phase, .connecting)
    XCTAssertFalse(audio.isClosed)
    audio.onConnectionChange?(.connected)
    XCTAssertEqual(store.phase, .connected)
    XCTAssertEqual(client.startedAgents, ["family"])
    XCTAssertEqual(system.connectedCount, 1)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  func testAnAgentOutsideTheRosterCannotStartACall() async {
    let client = VoiceClientDouble()
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    await transition(store, to: .choosing) { store.prepare() }
    store.start(agent)
    XCTAssertTrue(client.startedAgents.isEmpty)
    XCTAssertEqual(store.phase, .choosing)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  func testRemovingPickerCancelsAgentSelection() async {
    let client = VoiceClientDouble()
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .idle) { BruceVoicePresentation.dismissPicker(store) }
    XCTAssertEqual(client.closeCount, 1)
  }

  func testRemovingPickerPreservesActiveConversation() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let store = OpenClawVoiceStore(
      client: client, systemCall: VoiceSystemDouble(), makeAudio: { VoiceAudioDouble() })
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    BruceVoicePresentation.dismissPicker(store)
    XCTAssertEqual(store.phase, .connected)
    XCTAssertEqual(client.closeCount, 0)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  func testClosingOneOfTwoPickersPreservesTheOtherPicker() async {
    let client = VoiceClientDouble()
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    let first = UUID()
    let second = UUID()
    store.presentPicker(id: first)
    store.presentPicker(id: second)
    await transition(store, to: .choosing) { store.prepare() }
    BruceVoicePresentation.dismissPicker(store, presenterID: first)
    BruceVoicePresentation.dismissPicker(store, presenterID: first)
    BruceVoicePresentation.dismissPicker(store, presenterID: UUID())
    XCTAssertEqual(store.phase, .choosing)
    XCTAssertEqual(client.closeCount, 0)
    await transition(store, to: .idle) {
      BruceVoicePresentation.dismissPicker(store, presenterID: second)
    }
    XCTAssertEqual(client.closeCount, 1)
  }

  func testSignInBrowserDeliverySurvivesTheInitiatingWindowClosing() throws {
    let store = OpenClawVoiceStore(client: VoiceClientDouble())
    let first = UUID()
    let second = UUID()
    store.presentPicker(id: first)
    store.presentPicker(id: second)
    let url = try XCTUnwrap(URL(string: "https://example.invalid/sign-in"))
    let website = OpenClawVoiceStore.Browser(url: url, isWebsite: true)
    store.browser = website
    XCTAssertTrue(store.claimBrowserLaunch(id: website.id))
    XCTAssertFalse(store.claimBrowserLaunch(id: website.id))
    BruceVoicePresentation.dismissPicker(store, presenterID: first)
    let transfer = OpenClawVoiceStore.Browser(url: url, isWebsite: false)
    store.browser = transfer
    XCTAssertFalse(store.claimBrowserLaunch(id: website.id))
    XCTAssertTrue(store.claimBrowserLaunch(id: transfer.id))
    XCTAssertFalse(store.claimBrowserLaunch(id: transfer.id))
    store.browser = nil
    XCTAssertFalse(store.claimBrowserLaunch(id: transfer.id))
    BruceVoicePresentation.dismissPicker(store, presenterID: second)
  }

  func testDuplicateSignInContinuationDoesNotCancelAuthentication() async throws {
    let client = VoiceClientDouble()
    client.signInURL = try XCTUnwrap(URL(string: "https://example.invalid/sign-in"))
    let store = OpenClawVoiceStore(client: client, systemCall: VoiceSystemDouble())
    await transition(store, to: .signingIn) { store.prepare() }
    let browser = try XCTUnwrap(store.browser)
    await transition(store, to: .choosing) {
      store.continueSignIn(browserID: browser.id)
      store.continueSignIn(browserID: browser.id)
    }
    XCTAssertEqual(client.closeCount, 0)
    XCTAssertNil(store.browser)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
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

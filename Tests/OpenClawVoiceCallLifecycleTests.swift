import Combine
import SwiftUI
import XCTest

@testable import Bruce

@MainActor
final class OpenClawVoiceCallLifecycleTests: XCTestCase {
  private let agent = OpenClawAgent(id: "family", name: "Bruce — Family", identity: nil)

  func testHangupUsesThePlatformDestinationAndReconnectsForANewConversation() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let system = VoiceSystemDouble()
    let store = OpenClawVoiceStore(
      client: client, systemCall: system, makeAudio: { VoiceAudioDouble() })
    store.presentPicker(id: UUID())
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    await transition(store, to: postHangupPhase) { store.end() }
    XCTAssertEqual(client.rosterCount, 1)
    XCTAssertEqual(client.closeCount, 1)
    #if os(macOS)
      await transition(store, to: .choosing) { store.prepare() }
    #endif
    XCTAssertNil(store.agent)
    await transition(store, to: .connected) { store.start(self.agent) }
    XCTAssertEqual(client.startedAgents, ["family", "family"])
    XCTAssertEqual(client.connectCount, 2)
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  func testSystemMuteAndHangupControlTheSameConversation() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let system = VoiceSystemDouble()
    let audio = VoiceAudioDouble()
    let store = OpenClawVoiceStore(client: client, systemCall: system, makeAudio: { audio })
    store.presentPicker(id: UUID())
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    XCTAssertEqual(system.agents, [agent.id])
    system.onMute?(true)
    XCTAssertTrue(store.isMuted)
    XCTAssertEqual(audio.mutedValues, [true])
    await transition(store, to: postHangupPhase) { system.onEnd?() }
    XCTAssertTrue(audio.isClosed)
    XCTAssertEqual(system.endCount, 1)
    #if os(iOS)
      await transition(store, to: .idle) { store.end(returnToPicker: false) }
    #endif
  }

  func testRejectedSystemCallDoesNotStartRemoteVoice() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let system = VoiceSystemDouble()
    system.rejectsStart = true
    let audio = VoiceAudioDouble()
    let store = OpenClawVoiceStore(client: client, systemCall: system, makeAudio: { audio })
    store.presentPicker(id: UUID())
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .failed) { store.start(self.agent) }
    XCTAssertTrue(client.startedAgents.isEmpty)
    XCTAssertTrue(audio.isClosed)
    XCTAssertEqual(system.endCount, 1)
  }

  func testEndingWhileSystemStartIsPendingNeverStartsRemoteVoice() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let system = VoiceSystemDouble()
    system.blocksStart = true
    let starting = expectation(description: "System call start pending")
    system.onStart = { starting.fulfill() }
    let store = OpenClawVoiceStore(
      client: client, systemCall: system, makeAudio: { VoiceAudioDouble() })
    store.presentPicker(id: UUID())
    await transition(store, to: .choosing) { store.prepare() }
    store.start(agent)
    await fulfillment(of: [starting], timeout: 3)
    await transition(store, to: postHangupPhase) { store.end() }
    XCTAssertTrue(client.startedAgents.isEmpty)
    system.blocksStart = false
    system.onStart = nil
    #if os(macOS)
      await transition(store, to: .choosing) { store.prepare() }
    #endif
    await transition(store, to: .connected) { store.start(self.agent) }
    await transition(store, to: .idle) { store.end(returnToPicker: false) }
  }

  func testLeavingVoiceWhileHangupFinishesDoesNotReloadAHiddenPicker() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let store = OpenClawVoiceStore(
      client: client, systemCall: VoiceSystemDouble(), makeAudio: { VoiceAudioDouble() })
    store.presentPicker(id: UUID())
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    client.blocksClose = true
    let closing = expectation(description: "Closing remote voice")
    client.onClose = { closing.fulfill() }
    store.end()
    await fulfillment(of: [closing], timeout: 3)
    BruceVoicePresentation.dismissPicker(store)
    await transition(store, to: .idle) { client.finishClose?() }
    XCTAssertEqual(client.rosterCount, 1)
  }

  func testSystemFailureShowsFailureWithoutRestartingThePicker() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let system = VoiceSystemDouble()
    let store = OpenClawVoiceStore(
      client: client, systemCall: system, makeAudio: { VoiceAudioDouble() })
    store.presentPicker(id: UUID())
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    await transition(store, to: .failed) { system.onFailure?() }
    XCTAssertEqual(client.rosterCount, 1)
    XCTAssertNotNil(store.problem)
  }

  func testReturningBeforeHangupFinishesUsesThePlatformDestination() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let store = OpenClawVoiceStore(
      client: client, systemCall: VoiceSystemDouble(), makeAudio: { VoiceAudioDouble() })
    store.presentPicker(id: UUID())
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    client.blocksClose = true
    let closing = expectation(description: "Closing remote voice")
    client.onClose = { closing.fulfill() }
    store.end()
    await fulfillment(of: [closing], timeout: 3)
    BruceVoicePresentation.dismissPicker(store)
    store.prepare()
    await transition(store, to: postHangupPhase) { client.finishClose?() }
    XCTAssertEqual(client.rosterCount, 1)
    client.blocksClose = false
    #if os(iOS)
      await transition(store, to: .idle) { store.end(returnToPicker: false) }
    #endif
  }

  func testReturningDuringFailureTeardownPreservesTheError() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let system = VoiceSystemDouble()
    let store = OpenClawVoiceStore(
      client: client, systemCall: system, makeAudio: { VoiceAudioDouble() })
    store.presentPicker(id: UUID())
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    client.blocksClose = true
    let closing = expectation(description: "Failure teardown")
    client.onClose = { closing.fulfill() }
    system.onFailure?()
    await fulfillment(of: [closing], timeout: 3)
    store.prepare()
    await transition(store, to: .failed) { client.finishClose?() }
    XCTAssertEqual(client.rosterCount, 1)
    XCTAssertNotNil(store.problem)
  }

  func testSystemHangupWithNoVisibleVoiceUILeavesTheGatewayClosed() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let system = VoiceSystemDouble()
    let store = OpenClawVoiceStore(
      client: client, systemCall: system, makeAudio: { VoiceAudioDouble() })
    let presenter = UUID()
    store.presentPicker(id: presenter)
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    BruceVoicePresentation.dismissPicker(store, presenterID: presenter)
    XCTAssertEqual(store.phase, .connected)
    await transition(store, to: .idle) { system.onEnd?() }
    XCTAssertEqual(client.rosterCount, 1)
  }

  func testReturningDuringTheCallUsesThePlatformHangupDestination() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let system = VoiceSystemDouble()
    let store = OpenClawVoiceStore(
      client: client, systemCall: system, makeAudio: { VoiceAudioDouble() })
    let presenter = UUID()
    store.presentPicker(id: presenter)
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    BruceVoicePresentation.dismissPicker(store, presenterID: presenter)
    store.presentPicker(id: presenter)
    await transition(store, to: postHangupPhase) { system.onEnd?() }
    XCTAssertEqual(client.rosterCount, 1)
    #if os(iOS)
      await transition(store, to: .idle) { store.end(returnToPicker: false) }
    #endif
  }

  func testBackgroundedVoiceDoesNotRetainAPickerAfterSystemHangup() async {
    let client = VoiceClientDouble()
    client.roster = [agent]
    let system = VoiceSystemDouble()
    let store = OpenClawVoiceStore(
      client: client, systemCall: system, makeAudio: { VoiceAudioDouble() })
    let presenter = UUID()
    XCTAssertTrue(BruceVoicePresentation.shouldPresentPicker(isSelected: true, scenePhase: .active))
    XCTAssertTrue(
      BruceVoicePresentation.shouldPresentPicker(isSelected: true, scenePhase: .inactive))
    store.presentPicker(id: presenter)
    await transition(store, to: .choosing) { store.prepare() }
    await transition(store, to: .connected) { store.start(self.agent) }
    let isVisible = BruceVoicePresentation.shouldPresentPicker(
      isSelected: true, scenePhase: .background)
    XCTAssertFalse(isVisible)
    if !isVisible { BruceVoicePresentation.dismissPicker(store, presenterID: presenter) }
    XCTAssertEqual(store.phase, .connected)
    await transition(store, to: .idle) { system.onEnd?() }
    XCTAssertEqual(client.rosterCount, 1)
    XCTAssertFalse(
      BruceVoicePresentation.shouldPresentPicker(isSelected: false, scenePhase: .active))
  }

  private var postHangupPhase: OpenClawVoiceStore.Phase {
    #if os(iOS)
      .choosing
    #else
      .idle
    #endif
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

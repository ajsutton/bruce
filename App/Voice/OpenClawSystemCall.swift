#if os(iOS)
  import AVFoundation
  import CallKit
  import Foundation
  import OSLog
  @preconcurrency import StreamWebRTC

  @MainActor
  final class OpenClawSystemCall: NSObject, OpenClawSystemCalling {
    var onEnd: (() -> Void)?
    var onMute: ((Bool) -> Void)?
    var onFailure: (() -> Void)?
    private let controller = CXCallController()
    private var provider: CXProvider?
    private var callID: UUID?
    private var endingCalls: Set<UUID> = []
    private var startWaiter: CheckedContinuation<Void, any Error>?
    private let logger = Logger(subsystem: "net.symphonious.bruce", category: "SystemCall")

    override init() {
      super.init()
      let audio = RTCAudioSession.sharedInstance()
      audio.useManualAudio = true
      audio.isAudioEnabled = false
    }

    func start(agent: OpenClawAgent) async throws {
      try Task.checkCancellation()
      guard callID == nil else { throw OpenClawVoiceError.unavailable }
      if provider == nil {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        let provider = CXProvider(configuration: configuration)
        provider.setDelegate(self, queue: .main)
        self.provider = provider
      }
      let id = UUID()
      callID = id
      let action = CXStartCallAction(
        call: id, handle: CXHandle(type: .generic, value: agent.id))
      action.contactIdentifier = agent.displayName
      let update = CXCallUpdate()
      update.localizedCallerName = agent.displayName
      update.remoteHandle = action.handle
      update.supportsHolding = false
      update.supportsGrouping = false
      update.supportsUngrouping = false
      update.supportsDTMF = false
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          startWaiter = continuation
          controller.request(CXTransaction(action: action)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
              guard let self, self.callID == id else { return }
              self.startWaiter?.resume(throwing: error)
              self.startWaiter = nil
            }
          }
        }
      } onCancel: {
        Task { @MainActor [weak self] in
          guard self?.callID == id else { return }
          self?.end(failed: true)
        }
      }
      try Task.checkCancellation()
      guard callID == id else { throw CancellationError() }
      provider?.reportCall(with: id, updated: update)
    }

    func connected() {
      guard let callID else { return }
      provider?.reportOutgoingCall(with: callID, connectedAt: .now)
    }

    func setMuted(_ muted: Bool) {
      guard let id = callID else { return }
      let transaction = CXTransaction(action: CXSetMutedCallAction(call: id, muted: muted))
      controller.request(transaction) { [weak self] error in
        guard let error else { return }
        Task { @MainActor [weak self] in
          guard let self, self.callID == id else { return }
          self.logger.error("Call mute failed: \(error, privacy: .private)")
          self.onFailure?()
        }
      }
    }

    func end(failed: Bool) {
      guard let id = callID else { return }
      clearCall()
      if failed {
        provider?.reportCall(with: id, endedAt: .now, reason: .failed)
      } else {
        endingCalls.insert(id)
        controller.request(CXTransaction(action: CXEndCallAction(call: id))) { [weak self] error in
          guard let error else { return }
          Task { @MainActor [weak self] in
            guard let self, self.endingCalls.remove(id) != nil else { return }
            self.logger.error("Call end failed: \(error, privacy: .private)")
            self.provider?.reportCall(with: id, endedAt: .now, reason: .failed)
          }
        }
      }
    }

    private func clearCall() {
      callID = nil
      startWaiter?.resume(throwing: CancellationError())
      startWaiter = nil
      RTCAudioSession.sharedInstance().isAudioEnabled = false
    }
  }

  extension OpenClawSystemCall: @preconcurrency CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
      let hadCall = callID != nil
      endingCalls.removeAll()
      clearCall()
      if hadCall { onFailure?() }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
      guard action.callUUID == callID, startWaiter != nil else {
        action.fail()
        return
      }
      provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: .now)
      action.fulfill()
      startWaiter?.resume()
      startWaiter = nil
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
      if endingCalls.remove(action.callUUID) != nil {
        action.fulfill()
        return
      }
      guard action.callUUID == callID else {
        action.fail()
        return
      }
      clearCall()
      action.fulfill()
      onEnd?()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
      guard action.callUUID == callID else {
        action.fail()
        return
      }
      onMute?(action.isMuted)
      action.fulfill()
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
      guard let action = action as? CXCallAction else { return }
      if endingCalls.remove(action.callUUID) != nil {
        provider.reportCall(with: action.callUUID, endedAt: .now, reason: .failed)
      } else if action.callUUID == callID {
        onFailure?()
      }
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
      guard callID != nil else { return }
      let audio = RTCAudioSession.sharedInstance()
      audio.audioSessionDidActivate(audioSession)
      audio.isAudioEnabled = true
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
      let audio = RTCAudioSession.sharedInstance()
      audio.isAudioEnabled = false
      audio.audioSessionDidDeactivate(audioSession)
    }
  }
#else
  import Foundation

  @MainActor
  final class OpenClawSystemCall: OpenClawSystemCalling {
    var onEnd: (() -> Void)?
    var onMute: ((Bool) -> Void)?
    var onFailure: (() -> Void)?
    func start(agent: OpenClawAgent) async throws {}
    func connected() {}
    func setMuted(_ muted: Bool) { onMute?(muted) }
    func end(failed: Bool) {}
  }
#endif

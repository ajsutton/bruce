import AVFoundation
import Foundation
import OSLog
@preconcurrency import StreamWebRTC

enum OpenClawAudioState { case connected, disconnected, failed }

@MainActor
protocol OpenClawAudioCalling: AnyObject {
  var onConnectionChange: ((OpenClawAudioState) -> Void)? { get set }
  func offer() async throws -> String
  func accept(answer: String) async throws
  func setMuted(_ muted: Bool)
  func close()
}

@MainActor
final class OpenClawAudioCall: NSObject, OpenClawAudioCalling {
  private static let factory: RTCPeerConnectionFactory? = {
    guard RTCInitializeSSL() else { return nil }
    return RTCPeerConnectionFactory()
  }()
  private var peer: RTCPeerConnection?
  private var track: RTCAudioTrack?
  private var ownsAudioSession = false
  private var interruptionObservation: NSObjectProtocol?
  private let logger = Logger(subsystem: "net.symphonious.bruce", category: "VoiceAudio")
  var onConnectionChange: ((OpenClawAudioState) -> Void)?

  func offer() async throws -> String {
    let permitted = try await OpenClawMicrophonePermission().request()
    guard permitted else { throw OpenClawVoiceError.microphoneDenied }
    guard let factory = Self.factory else { throw OpenClawVoiceError.unavailable }
    try Task.checkCancellation()
    #if os(iOS)
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(
        .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
      try audio.setActive(true)
      ownsAudioSession = true
      interruptionObservation = NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification, object: audio, queue: .main
      ) { [weak self] notification in
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          AVAudioSession.InterruptionType(rawValue: raw) == .began
        else { return }
        Task { @MainActor [weak self] in self?.onConnectionChange?(.failed) }
      }
    #endif
    let configuration = RTCConfiguration()
    configuration.sdpSemantics = .unifiedPlan
    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    guard
      let peer = factory.peerConnection(
        with: configuration, constraints: constraints, delegate: self)
    else {
      throw OpenClawVoiceError.unavailable
    }
    self.peer = peer
    let source = factory.audioSource(with: constraints)
    let track = factory.audioTrack(with: source, trackId: UUID().uuidString)
    self.track = track
    peer.add(track, streamIds: ["bruce-voice"])
    let offer = try await peer.offer(
      for: RTCMediaConstraints(
        mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "false"],
        optionalConstraints: nil
      ))
    try Task.checkCancellation()
    try await peer.setLocalDescription(offer)
    return offer.sdp
  }

  func accept(answer: String) async throws {
    guard let peer else { throw OpenClawVoiceError.disconnected }
    try Task.checkCancellation()
    try await peer.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer))
  }

  func setMuted(_ muted: Bool) { track?.isEnabled = !muted }

  func close() {
    onConnectionChange = nil
    if let interruptionObservation {
      NotificationCenter.default.removeObserver(interruptionObservation)
      self.interruptionObservation = nil
    }
    track?.isEnabled = false
    track = nil
    peer?.close()
    peer = nil
    #if os(iOS)
      if ownsAudioSession {
        ownsAudioSession = false
        do {
          try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch { /* The call is already closed; the system owns any interrupted route. */  }
      }
    #endif
  }
}

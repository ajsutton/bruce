import Foundation
@preconcurrency import StreamWebRTC

extension OpenClawAudioCall: RTCPeerConnectionDelegate {
  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState
  ) {
    switch newState {
    case .connected, .completed:
      Task { @MainActor [weak self] in self?.onConnectionChange?(.connected) }
    case .failed, .closed:
      Task { @MainActor [weak self] in self?.onConnectionChange?(.failed) }
    case .disconnected:
      Task { @MainActor [weak self] in self?.onConnectionChange?(.disconnected) }
    case .new, .checking, .count: break
    @unknown default:
      Task { @MainActor [weak self] in self?.onConnectionChange?(.failed) }
    }
  }

  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState
  ) {}
  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream
  ) {}
  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream
  ) {}
  nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState
  ) {}
  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate
  ) {}
  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]
  ) {}
  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel
  ) {}
}

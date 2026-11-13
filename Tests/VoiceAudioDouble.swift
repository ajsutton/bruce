import Foundation

@testable import Bruce

@MainActor
final class VoiceAudioDouble: OpenClawAudioCalling {
  var onConnectionChange: ((OpenClawAudioState) -> Void)?
  var onOffer: (() -> Void)?
  var blocksOffer = false
  var isClosed = false
  var mutedValues: [Bool] = []
  private var offerCompletion: (@Sendable (Bool) -> Void)?

  func offer() async throws -> String {
    if blocksOffer {
      _ = try await OpenClawMicrophonePermission { completion in
        self.offerCompletion = completion
        self.onOffer?()
      }.request()
    }
    return "offer"
  }

  func accept(answer: String) async throws { onConnectionChange?(.connected) }
  func setMuted(_ muted: Bool) { mutedValues.append(muted) }
  func close() {
    isClosed = true
    onConnectionChange = nil
  }
}

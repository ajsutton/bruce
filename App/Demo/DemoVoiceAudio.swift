import AVFoundation
import Foundation

/// Local speech only: demo calls never acquire a microphone, socket or CallKit call.
@MainActor
final class DemoVoiceAudio: OpenClawAudioCalling {
  var onConnectionChange: ((OpenClawAudioState) -> Void)?
  private let synthesizer = AVSpeechSynthesizer()
  private var isOpen = false
  private var isMuted = false

  func offer() async throws -> String {
    try Task.checkCancellation()
    isOpen = true
    isMuted = false
    return "demo"
  }

  func accept(answer: String) async throws {
    try Task.checkCancellation()
    guard isOpen else { throw CancellationError() }
    onConnectionChange?(.connected)
    speak(answer)
  }

  func speak(_ text: String) {
    guard isOpen, !isMuted else { return }
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(
      language: Locale.current.language.languageCode?.identifier)
    synthesizer.speak(utterance)
  }

  func setMuted(_ muted: Bool) {
    isMuted = muted
    if muted { synthesizer.stopSpeaking(at: .immediate) }
  }

  func close() {
    isOpen = false
    synthesizer.stopSpeaking(at: .immediate)
    onConnectionChange = nil
  }
}

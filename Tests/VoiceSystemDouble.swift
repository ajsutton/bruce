import Foundation

@testable import Bruce

@MainActor
final class VoiceSystemDouble: OpenClawSystemCalling {
  var onEnd: (() -> Void)?
  var onMute: ((Bool) -> Void)?
  var onFailure: (() -> Void)?
  var agents: [String] = []
  var endCount = 0
  var connectedCount = 0
  var rejectsStart = false
  var blocksStart = false
  var onStart: (() -> Void)?
  private var startWaiter: CheckedContinuation<Void, any Error>?
  func start(agent: OpenClawAgent) async throws {
    agents.append(agent.id)
    if rejectsStart { throw OpenClawVoiceError.unavailable }
    if blocksStart {
      try await withCheckedThrowingContinuation { continuation in
        startWaiter = continuation
        onStart?()
      }
    }
  }
  func connected() { connectedCount += 1 }
  func setMuted(_ muted: Bool) { onMute?(muted) }
  func end(failed: Bool) {
    endCount += 1
    startWaiter?.resume(throwing: CancellationError())
    startWaiter = nil
  }
}

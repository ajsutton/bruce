import Foundation

@testable import Bruce

@MainActor
final class VoiceClientDouble: OpenClawVoiceServing {
  var onDisconnect: (() -> Void)?
  var roster: [OpenClawAgent] = []
  var startedAgents: [String] = []
  var closeCount = 0
  var blocksClose = false
  var onClose: (() -> Void)?
  var finishClose: (() -> Void)?
  var rosterCount = 0
  var signInURL: URL?

  func agents(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws
    -> [OpenClawAgent]
  {
    rosterCount += 1
    if let signInURL { try await signIn(signInURL, true) }
    return roster
  }

  func start(agentID: String, offer: String) async throws -> String {
    startedAgents.append(agentID)
    return "answer"
  }

  func connected() {}
  func close() async throws {
    closeCount += 1
    if blocksClose {
      await withCheckedContinuation { continuation in
        finishClose = { continuation.resume() }
        onClose?()
      }
    }
  }
}

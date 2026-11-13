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
  var failsRoster = false
  var blocksRoster = false
  var onRoster: (() -> Void)?
  var finishRoster: (() -> Void)?
  var rosterCount = 0
  var connectCount = 0
  var connectSignInURL: URL?
  var signInURL: URL?

  func agents(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws
    -> [OpenClawAgent]
  {
    rosterCount += 1
    if failsRoster { throw OpenClawVoiceError.unavailable }
    if blocksRoster {
      await withCheckedContinuation { continuation in
        finishRoster = { continuation.resume() }
        onRoster?()
      }
    }
    if let signInURL { try await signIn(signInURL, true) }
    return roster
  }

  func connect(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws {
    connectCount += 1
    if let connectSignInURL { try await signIn(connectSignInURL, true) }
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

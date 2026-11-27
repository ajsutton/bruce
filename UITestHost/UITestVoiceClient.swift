import Foundation

@MainActor
final class UITestVoiceClient: OpenClawVoiceServing {
  var onDisconnect: (() -> Void)?
  func agents(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws
    -> [OpenClawAgent]
  {
    []
  }
  func connect(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws {}
  func start(agentID: String, offer: String) async throws -> String {
    throw OpenClawVoiceError.unavailable
  }
  func connected() {}
  func close() async throws {}
  func logOut() throws {}
}

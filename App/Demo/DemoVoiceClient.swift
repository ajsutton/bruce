import Foundation

@MainActor
final class DemoVoiceClient: OpenClawVoiceServing {
  var onDisconnect: (() -> Void)?
  private let copy: DemoCopy

  init(mode: BruceMode = .standard) {
    copy = DemoCopy(mode: mode)
  }

  func agents(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws
    -> [OpenClawAgent]
  {
    try Task.checkCancellation()
    return [
      OpenClawAgent(id: "house", name: copy.houseAgent, identity: nil),
      OpenClawAgent(id: "family", name: copy.familyAgent, identity: nil),
    ]
  }

  func connect(signIn: @escaping @MainActor (URL, Bool) async throws -> Void) async throws {
    try Task.checkCancellation()
  }

  func start(agentID: String, offer: String) async throws -> String {
    try Task.checkCancellation()
    guard agentID == "house" || agentID == "family" else { throw DemoHomeError.unknownEntity }
    return copy.welcome
  }

  func connected() {}
  func close() async throws {}
  func logOut() throws {}
}

import Foundation

@MainActor
final class DemoSystemCall: OpenClawSystemCalling {
  var onEnd: (() -> Void)?
  var onMute: ((Bool) -> Void)?
  var onFailure: (() -> Void)?

  func start(agent: OpenClawAgent) async throws { try Task.checkCancellation() }
  func connected() {}
  func setMuted(_ muted: Bool) { onMute?(muted) }
  func end(failed: Bool) {}
}

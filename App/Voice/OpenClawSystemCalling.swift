import Foundation

/// The system owns call controls; the voice store owns the conversation.
@MainActor
protocol OpenClawSystemCalling: AnyObject {
  var onEnd: (() -> Void)? { get set }
  var onMute: ((Bool) -> Void)? { get set }
  var onFailure: (() -> Void)? { get set }
  func start(agent: OpenClawAgent) async throws
  func connected()
  func setMuted(_ muted: Bool)
  func end(failed: Bool)
}

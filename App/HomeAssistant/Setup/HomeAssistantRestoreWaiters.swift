import Foundation

/// Lets individual consumers stop waiting without cancelling the shared credential restore.
@MainActor
final class HomeAssistantRestoreWaiters {
  enum Outcome {
    case finished
    case invalidated
  }

  private var result: Outcome?
  private var continuations: [UUID: CheckedContinuation<Outcome, Never>] = [:]

  func wait() async -> Outcome {
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard result == nil, !Task.isCancelled else {
          continuation.resume(returning: Task.isCancelled ? .invalidated : (result ?? .invalidated))
          return
        }
        continuations[id] = continuation
      }
    } onCancel: {
      Task { @MainActor in
        self.continuations.removeValue(forKey: id)?.resume(returning: .invalidated)
      }
    }
  }

  func finish(_ outcome: Outcome = .finished) {
    guard result == nil else { return }
    result = outcome
    let pending = continuations.values
    continuations.removeAll()
    for continuation in pending { continuation.resume(returning: outcome) }
  }
}

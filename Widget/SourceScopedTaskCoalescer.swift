import Foundation

actor SourceScopedTaskCoalescer<Value: Sendable> {
  private struct InFlight {
    let id: UUID
    let sourceIdentifier: String?
    let task: Task<Value, Never>
  }

  private var inFlight: InFlight?

  func value(
    for sourceIdentifier: String?,
    operation: @escaping @Sendable () async -> Value
  ) async -> Value {
    if let inFlight, inFlight.sourceIdentifier == sourceIdentifier {
      return await inFlight.task.value
    }
    let id = UUID()
    let task = Task { await operation() }
    inFlight = InFlight(id: id, sourceIdentifier: sourceIdentifier, task: task)
    let value = await task.value
    if inFlight?.id == id {
      inFlight = nil
    }
    return value
  }
}

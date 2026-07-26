import Foundation

actor HomeAssistantPersistenceGate {
  private struct Waiter {
    let id: UUID
    let continuation: CheckedContinuation<Void, any Error>
  }

  private var isLocked = false
  private var waiters: [Waiter] = []
  private let waiterQueued: @Sendable () -> Void
  private let cancellationDeferral: @Sendable () async -> Void

  init(
    waiterQueued: @escaping @Sendable () -> Void = {},
    cancellationDeferral: @escaping @Sendable () async -> Void = {}
  ) {
    self.waiterQueued = waiterQueued
    self.cancellationDeferral = cancellationDeferral
  }

  func acquire() async throws {
    try Task.checkCancellation()
    guard isLocked else {
      isLocked = true
      return
    }
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiters.append(Waiter(id: id, continuation: continuation))
        waiterQueued()
      }
    } onCancel: {
      Task { [cancellationDeferral] in
        await cancellationDeferral()
        await self.cancelWaiter(id: id)
      }
    }
    do {
      try Task.checkCancellation()
    } catch {
      release()
      throw error
    }
  }

  func release() {
    guard !waiters.isEmpty else {
      isLocked = false
      return
    }
    waiters.removeFirst().continuation.resume()
  }

  private func cancelWaiter(id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else {
      return
    }
    waiters.remove(at: index).continuation.resume(throwing: CancellationError())
  }
}

func withHomeAssistantPersistence<T: Sendable>(
  isolation: isolated (any Actor)? = #isolation,
  gate: HomeAssistantPersistenceGate,
  operation: () async throws -> T
) async throws -> T {
  try await gate.acquire()
  let result: Result<T, any Error>
  do {
    result = .success(try await operation())
  } catch {
    result = .failure(error)
  }
  await gate.release()
  return try result.get()
}

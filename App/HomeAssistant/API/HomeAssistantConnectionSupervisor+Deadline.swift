import Foundation

extension HomeAssistantConnectionSupervisor {
  func withPhaseDeadline<Value: Sendable>(
    operation: @escaping @Sendable () async throws -> Value,
    onTimeout: @escaping @Sendable () async -> Void
  ) async throws -> Value {
    let race = HomeAssistantPhaseDeadlineRace<Value>()
    return try await withTaskCancellationHandler {
      let operationTask = Task.detached {
        let result: Result<Value, any Error>
        do {
          result = .success(try await operation())
        } catch {
          result = .failure(error)
        }
        await race.resolve(result)
      }
      let deadlineTask = Task.detached { [clock, phaseDeadline] in
        do {
          try await clock.sleep(phaseDeadline, nil)
        } catch {
          await race.resolve(.failure(error))
          return
        }
        guard await race.claim() else { return }
        await onTimeout()
        await race.resolveClaimed(.failure(URLError(.timedOut)))
      }
      defer {
        operationTask.cancel()
        deadlineTask.cancel()
      }
      return try await race.value().get()
    } onCancel: {
      Task {
        await race.resolve(.failure(CancellationError()))
      }
    }
  }
}

private actor HomeAssistantPhaseDeadlineRace<Value: Sendable> {
  private enum State {
    case pending
    case claimed
    case resolved(Result<Value, any Error>)
  }

  private var state = State.pending
  private var continuation: CheckedContinuation<Result<Value, any Error>, Never>?

  func claim() -> Bool {
    guard case .pending = state else { return false }
    state = .claimed
    return true
  }

  func resolve(_ result: Result<Value, any Error>) {
    guard case .pending = state else { return }
    finish(with: result)
  }

  func resolveClaimed(_ result: Result<Value, any Error>) {
    guard case .claimed = state else { return }
    finish(with: result)
  }

  func value() async -> Result<Value, any Error> {
    if case .resolved(let result) = state {
      return result
    }
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  private func finish(with result: Result<Value, any Error>) {
    state = .resolved(result)
    continuation?.resume(returning: result)
    continuation = nil
  }
}

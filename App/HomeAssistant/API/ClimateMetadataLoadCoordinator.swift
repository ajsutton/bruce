import Foundation

final class ClimateMetadataLoadCoordinator: @unchecked Sendable {
  typealias Output = [String: HomeAssistantClimateMetadata]

  private typealias LoadResult = Result<Output, any Error>

  private let lock = NSLock()
  private var activeLoad: Task<Void, Never>?
  private var waiters: [UUID: ClimateMetadataLoadWaiter] = [:]
  private var isDraining = false

  func load(
    timeout: Duration,
    operation: @escaping @Sendable () async throws -> Output
  ) async throws -> Output {
    let waiter = ClimateMetadataLoadWaiter()
    register(waiter, timeout: timeout, operation: operation)
    let result = await withTaskCancellationHandler {
      await waiter.result()
    } onCancel: {
      complete(waiter, with: .failure(CancellationError()))
    }
    return try result.get()
  }

  private func register(
    _ waiter: ClimateMetadataLoadWaiter,
    timeout: Duration,
    operation: @escaping @Sendable () async throws -> Output
  ) {
    let shouldUseFallback = lock.withLock {
      guard !isDraining else {
        return true
      }
      waiters[waiter.id] = waiter
      if activeLoad == nil {
        activeLoad = Task {
          do {
            finish(with: .success(try await operation()))
          } catch {
            finish(with: .failure(error))
          }
        }
      }
      return false
    }
    guard !shouldUseFallback else {
      waiter.resolve(.success([:]))
      return
    }
    waiter.startTimeout(after: timeout) { [weak self, weak waiter] in
      guard let self, let waiter else {
        return
      }
      complete(waiter, with: .success([:]))
    }
  }

  private func complete(_ waiter: ClimateMetadataLoadWaiter, with result: LoadResult) {
    let loadToCancel = lock.withLock {
      guard waiters.removeValue(forKey: waiter.id) != nil else {
        return Optional<Task<Void, Never>>.none
      }
      guard waiters.isEmpty else {
        return nil
      }
      isDraining = true
      return activeLoad
    }
    loadToCancel?.cancel()
    waiter.resolve(result)
  }

  private func finish(with result: LoadResult) {
    let waiters = lock.withLock {
      activeLoad = nil
      isDraining = false
      let waiters = Array(self.waiters.values)
      self.waiters.removeAll()
      return waiters
    }
    waiters.forEach {
      $0.resolve(result)
    }
  }
}

private final class ClimateMetadataLoadWaiter: @unchecked Sendable {
  typealias LoadResult = Result<[String: HomeAssistantClimateMetadata], any Error>

  let id = UUID()

  private let lock = NSLock()
  private var continuation: CheckedContinuation<LoadResult, Never>?
  private var pendingResult: LoadResult?
  private var timeoutTask: Task<Void, Never>?
  private var isFinished = false

  func result() async -> LoadResult {
    await withCheckedContinuation { continuation in
      let pendingResult = lock.withLock {
        guard let pendingResult else {
          self.continuation = continuation
          return Optional<LoadResult>.none
        }
        self.pendingResult = nil
        return pendingResult
      }
      if let pendingResult {
        continuation.resume(returning: pendingResult)
      }
    }
  }

  func startTimeout(
    after timeout: Duration,
    onTimeout: @escaping @Sendable () -> Void
  ) {
    let timeoutTask = Task {
      do {
        try await Task.sleep(for: timeout)
        onTimeout()
      } catch is CancellationError {
      } catch {
        onTimeout()
      }
    }
    let shouldCancel = lock.withLock {
      guard !isFinished else {
        return true
      }
      self.timeoutTask = timeoutTask
      return false
    }
    if shouldCancel {
      timeoutTask.cancel()
    }
  }

  func resolve(_ result: LoadResult) {
    let completion = lock.withLock {
      guard !isFinished else {
        return (
          continuation: Optional<CheckedContinuation<LoadResult, Never>>.none,
          timeoutTask: Optional<Task<Void, Never>>.none
        )
      }
      isFinished = true
      let continuation = self.continuation
      if continuation == nil {
        pendingResult = result
      }
      self.continuation = nil
      let timeoutTask = self.timeoutTask
      self.timeoutTask = nil
      return (continuation, timeoutTask)
    }
    completion.timeoutTask?.cancel()
    completion.continuation?.resume(returning: result)
  }
}

import Foundation

protocol HomeAssistantBufferedUpdate: Sendable {
  var isLiveUpdate: Bool { get }
  func preservingControlTransition(from update: Self) -> Self?
  func preservingLiveTransition(from update: Self) -> Self?
}

extension HomeAssistantBufferedUpdate {
  func preservingLiveTransition(from _: Self) -> Self? {
    nil
  }
}

private struct HomeAssistantBufferedUpdateWaiter<Update: HomeAssistantBufferedUpdate> {
  let continuation: CheckedContinuation<Update?, any Error>
}

private enum HomeAssistantBufferedUpdateNextAction<Update: HomeAssistantBufferedUpdate> {
  case value(Update)
  case wait
  case finish
  case fail(any Error)
}

private final class BufferedUpdateIteratorLifetime: @unchecked Sendable {
  private let cancelStream: @Sendable () -> Void

  init(cancelStream: @escaping @Sendable () -> Void) {
    self.cancelStream = cancelStream
  }

  deinit {
    cancelStream()
  }
}

struct HomeAssistantBufferedUpdateStream<Update: HomeAssistantBufferedUpdate>:
  AsyncSequence, Sendable
{
  typealias Element = Update

  enum Termination: Sendable {
    case cancelled
    case finished
  }

  final class Continuation: @unchecked Sendable {
    fileprivate let storage: Storage

    fileprivate init(storage: Storage) {
      self.storage = storage
    }

    var onTermination: (@Sendable (Termination) -> Void)? {
      get { storage.terminationHandler }
      set { storage.setTerminationHandler(newValue) }
    }

    func yield(_ update: Update) {
      storage.yield(update)
    }

    func finish(throwing error: (any Error)? = nil) {
      storage.finish(throwing: error)
    }
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    fileprivate let storage: Storage
    private let lifetime: BufferedUpdateIteratorLifetime

    fileprivate init(storage: Storage) {
      self.storage = storage
      lifetime = BufferedUpdateIteratorLifetime {
        storage.cancel()
      }
    }

    mutating func next(
      isolation actor: isolated (any Actor)?
    ) async throws -> Update? {
      try await storage.next(isolation: actor)
    }
  }

  private let storage: Storage

  init(_ build: (Continuation) -> Void) {
    let storage = Storage()
    self.storage = storage
    build(Continuation(storage: storage))
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(storage: storage)
  }

  func cancel() {
    storage.cancel()
  }
}

extension HomeAssistantBufferedUpdateStream {
  fileprivate final class Storage: @unchecked Sendable {
    private let lock = NSLock()
    private var buffered: [Update] = []
    private var waiter: HomeAssistantBufferedUpdateWaiter<Update>?
    private var terminalError: (any Error)?
    private var isFinished = false
    private var terminalReason: Termination?
    private var storedTerminationHandler: (@Sendable (Termination) -> Void)?

    var terminationHandler: (@Sendable (Termination) -> Void)? {
      lock.withLock { storedTerminationHandler }
    }

    func setTerminationHandler(
      _ handler: (@Sendable (Termination) -> Void)?
    ) {
      let reason = lock.withLock {
        guard isFinished else {
          storedTerminationHandler = handler
          return nil as Termination?
        }
        return terminalReason
      }
      if let reason {
        handler?(reason)
      }
    }

    func yield(_ update: Update) {
      let waiting = lock.withLock {
        guard !isFinished else {
          return nil as HomeAssistantBufferedUpdateWaiter<Update>?
        }
        if let waiter {
          self.waiter = nil
          return waiter
        }
        buffer(update)
        return nil
      }
      waiting?.continuation.resume(returning: update)
    }

    func finish(throwing error: (any Error)?) {
      let state = lock.withLock {
        guard !isFinished else {
          return (
            nil as HomeAssistantBufferedUpdateWaiter<Update>?,
            nil as (@Sendable (Termination) -> Void)?
          )
        }
        isFinished = true
        terminalReason = .finished
        terminalError = error
        let waiting = waiter
        waiter = nil
        let handler = storedTerminationHandler
        storedTerminationHandler = nil
        return (waiting, handler)
      }
      if let error {
        state.0?.continuation.resume(throwing: error)
      } else {
        state.0?.continuation.resume(returning: nil)
      }
      state.1?(.finished)
    }

    func next(
      isolation _: isolated (any Actor)?
    ) async throws -> Update? {
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let action = lock.withLock {
            if Task.isCancelled {
              return HomeAssistantBufferedUpdateNextAction<Update>.fail(
                CancellationError()
              )
            }
            if !buffered.isEmpty {
              return .value(buffered.removeFirst())
            }
            if isFinished {
              return terminalError.map(
                HomeAssistantBufferedUpdateNextAction<Update>.fail
              )
                ?? .finish
            }
            waiter = HomeAssistantBufferedUpdateWaiter(continuation: continuation)
            return .wait
          }
          switch action {
          case .value(let update):
            continuation.resume(returning: update)
          case .finish:
            continuation.resume(returning: nil)
          case .fail(let error):
            continuation.resume(throwing: error)
          case .wait:
            break
          }
        }
      } onCancel: {
        self.cancel()
      }
    }

    func cancel() {
      let state = lock.withLock {
        guard !isFinished else {
          return (
            nil as CheckedContinuation<Update?, any Error>?,
            nil as (@Sendable (Termination) -> Void)?
          )
        }
        isFinished = true
        terminalReason = .cancelled
        buffered = []
        terminalError = CancellationError()
        let continuation = waiter?.continuation
        waiter = nil
        let handler = storedTerminationHandler
        storedTerminationHandler = nil
        return (continuation, handler)
      }
      state.0?.resume(throwing: CancellationError())
      state.1?(.cancelled)
    }

    private func buffer(_ update: Update) {
      if update.isLiveUpdate {
        let control = buffered.last(where: { !$0.isLiveUpdate })
        let pendingLiveUpdates = buffered.filter(\.isLiveUpdate)
        let newerLiveTransition = pendingLiveUpdates.last.flatMap {
          update.preservingLiveTransition(from: $0)
        }
        let existingLiveTransition =
          pendingLiveUpdates.count > 1 ? pendingLiveUpdates.first : nil
        buffered = [
          control.flatMap {
            update.preservingControlTransition(from: $0)
          },
          newerLiveTransition ?? existingLiveTransition,
          update,
        ].compactMap(\.self)
      } else {
        buffered.append(update)
        if buffered.count > 2 {
          buffered.removeFirst(buffered.count - 2)
        }
      }
    }

  }
}

import XCTest

@testable import Bruce

@MainActor
final class BufferedUpdateStreamCancellationTests: XCTestCase {
  typealias Stream = HomeAssistantBufferedUpdateStream<HomeAssistantStateUpdate>

  func testCancellationWhileBufferedValueIsBeingHandledTerminatesOnce() async throws {
    let setup = try streamSetup()
    let valueReceived = expectation(description: "Buffered value received")
    let gate = BufferedUpdateStreamCancellationGate()
    setup.continuation.yield(.live([]))
    let consumer = Task {
      var iterator = setup.stream.makeAsyncIterator()
      _ = try await iterator.next()
      valueReceived.fulfill()
      try await gate.wait()
    }
    await fulfillment(of: [valueReceived, gate.started], timeout: 1)

    consumer.cancel()
    _ = try? await consumer.value
    await fulfillment(of: [setup.terminated], timeout: 1)
    setup.stream.cancel()
  }

  func testAlreadyCancelledTaskEnteringNextTerminatesOnce() async throws {
    let setup = try streamSetup()
    let gate = BufferedUpdateStreamGate()
    let consumer = Task {
      var iterator = setup.stream.makeAsyncIterator()
      await gate.wait()
      _ = try await iterator.next()
    }
    await fulfillment(of: [gate.started], timeout: 1)

    consumer.cancel()
    gate.open()
    _ = try? await consumer.value
    await fulfillment(of: [setup.terminated], timeout: 1)
    setup.stream.cancel()
  }

  func testCancellationWhileWaitingForNextTerminatesOnce() async throws {
    let setup = try streamSetup()
    let consumerWaiting = expectation(description: "Consumer waiting for next value")
    let consumer = Task { @MainActor in
      var iterator = setup.stream.makeAsyncIterator()
      consumerWaiting.fulfill()
      _ = try await iterator.next(isolation: MainActor.shared)
    }
    await fulfillment(of: [consumerWaiting], timeout: 1)

    consumer.cancel()
    _ = try? await consumer.value
    await fulfillment(of: [setup.terminated], timeout: 1)
    setup.stream.cancel()
  }

  func testTerminationHandlerInstalledAfterFinishRunsOnce() async throws {
    var continuation: Stream.Continuation?
    let stream = Stream {
      continuation = $0
    }
    let streamContinuation = try XCTUnwrap(continuation)
    streamContinuation.finish()
    let terminated = expectation(description: "Late termination handler called")
    terminated.assertForOverFulfill = true

    streamContinuation.onTermination = { termination in
      if case .finished = termination {
        terminated.fulfill()
      }
    }
    await fulfillment(of: [terminated], timeout: 1)
    stream.cancel()
  }

  private func streamSetup() throws -> BufferedUpdateStreamTestSetup {
    var continuation: Stream.Continuation?
    let stream = Stream {
      continuation = $0
    }
    let terminated = expectation(description: "Stream terminated exactly once")
    terminated.assertForOverFulfill = true
    continuation?.onTermination = { _ in
      terminated.fulfill()
    }
    return BufferedUpdateStreamTestSetup(
      stream: stream,
      continuation: try XCTUnwrap(continuation),
      terminated: terminated
    )
  }
}

private struct BufferedUpdateStreamTestSetup {
  let stream: HomeAssistantBufferedUpdateStream<HomeAssistantStateUpdate>
  let continuation:
    HomeAssistantBufferedUpdateStream<
      HomeAssistantStateUpdate
    >.Continuation
  let terminated: XCTestExpectation
}

private final class BufferedUpdateStreamGate: @unchecked Sendable {
  let started = XCTestExpectation(description: "Cancellation gate reached")

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    await withCheckedContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func open() {
    let continuation = lock.withLock {
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume()
  }
}

private final class BufferedUpdateStreamCancellationGate: @unchecked Sendable {
  let started = XCTestExpectation(description: "Cancellation-aware gate reached")

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, any Error>?
  private var isCancelled = false

  func wait() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let shouldCancel = lock.withLock {
          guard !isCancelled else { return true }
          self.continuation = continuation
          return false
        }
        started.fulfill()
        if shouldCancel {
          continuation.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      self.cancel()
    }
  }

  private func cancel() {
    let continuation = lock.withLock {
      isCancelled = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume(throwing: CancellationError())
  }
}

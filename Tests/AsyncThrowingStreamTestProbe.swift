import Foundation
import XCTest

final class AsyncThrowingStreamTestProbe<Element: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var results: [Result<Element, any Error>] = []
  private var expectations: [Int: XCTestExpectation] = [:]
  private var observation: Task<Void, Never>?

  init(_ stream: AsyncThrowingStream<Element, any Error>) {
    observation = Task { [weak self] in
      do {
        for try await value in stream {
          self?.record(.success(value))
        }
        self?.record(.failure(StreamProbeError.finished))
      } catch {
        self?.record(.failure(error))
      }
    }
  }

  deinit {
    observation?.cancel()
  }

  func received(at index: Int) -> XCTestExpectation {
    lock.withLock {
      if let expectation = expectations[index] {
        return expectation
      }
      let expectation = XCTestExpectation(
        description: "Async stream result \(index) received"
      )
      expectations[index] = expectation
      if results.indices.contains(index) {
        expectation.fulfill()
      }
      return expectation
    }
  }

  func value(at index: Int) throws -> Element {
    let result = lock.withLock {
      results.indices.contains(index) ? results[index] : nil
    }
    return try XCTUnwrap(result, "No async stream result at index \(index).").get()
  }

  func cancel() async {
    observation?.cancel()
    await observation?.value
    observation = nil
  }

  private func record(_ result: Result<Element, any Error>) {
    let expectation = lock.withLock {
      let index = results.count
      results.append(result)
      return expectations[index]
    }
    expectation?.fulfill()
  }
}

private enum StreamProbeError: Error {
  case finished
}

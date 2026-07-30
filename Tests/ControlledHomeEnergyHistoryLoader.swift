import Foundation
import XCTest

@testable import Bruce

final class ControlledHomeEnergyHistoryLoader:
  HomeAssistantHomeEnergyLoading, @unchecked Sendable
{
  typealias Update = HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>

  let updateStreamStarted = XCTestExpectation(
    description: "Home energy update stream started"
  )

  private let lock = NSLock()
  private let historyStartedExpectations: [XCTestExpectation]
  private let historyFinishedExpectations: [XCTestExpectation]
  private var nextHistoryRequest = 0
  private var historyContinuations: [Int: CheckedContinuation<HomeEnergyPriceHistory, any Error>] =
    [:]
  private var updateContinuation: AsyncThrowingStream<Update, any Error>.Continuation?

  init(historyRequestCount: Int) {
    historyStartedExpectations = (0..<historyRequestCount).map {
      XCTestExpectation(description: "Price history load \($0) started")
    }
    historyFinishedExpectations = (0..<historyRequestCount).map {
      XCTestExpectation(description: "Price history load \($0) finished")
    }
  }

  var providesContinuousEnergyUpdates: Bool { true }

  var historyRequestCount: Int {
    lock.withLock { nextHistoryRequest }
  }

  func historyStarted(at index: Int) -> XCTestExpectation {
    historyStartedExpectations[index]
  }

  func historyFinished(at index: Int) -> XCTestExpectation {
    historyFinishedExpectations[index]
  }

  func homeEnergyUpdates() -> AsyncThrowingStream<Update, any Error> {
    AsyncThrowingStream { continuation in
      lock.withLock {
        updateContinuation = continuation
      }
      updateStreamStarted.fulfill()
    }
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }

  func loadHomeEnergyPriceHistory() async throws -> HomeEnergyPriceHistory {
    let request = lock.withLock {
      let request = nextHistoryRequest
      nextHistoryRequest += 1
      return request
    }
    defer {
      historyFinishedExpectations[request].fulfill()
    }
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        historyContinuations[request] = continuation
      }
      historyStartedExpectations[request].fulfill()
    }
  }

  func yield(_ update: Update) {
    lock.withLock { updateContinuation }?.yield(update)
  }

  func finishUpdates() {
    let continuation = lock.withLock {
      let continuation = updateContinuation
      updateContinuation = nil
      return continuation
    }
    continuation?.finish()
  }

  func succeedHistory(_ request: Int, with history: HomeEnergyPriceHistory) {
    let continuation = lock.withLock {
      historyContinuations.removeValue(forKey: request)
    }
    continuation?.resume(returning: history)
  }

  func failHistory(_ request: Int, with error: any Error) {
    let continuation = lock.withLock {
      historyContinuations.removeValue(forKey: request)
    }
    continuation?.resume(throwing: error)
  }
}

final class ControlledHomeEnergyDateSequence: @unchecked Sendable {
  private let lock = NSLock()
  private let dates: [Date]
  private let requestedExpectations: [XCTestExpectation]
  private var nextIndex = 0

  init(_ dates: [Date]) {
    self.dates = dates
    requestedExpectations = dates.indices.map {
      XCTestExpectation(description: "Home energy date \($0) requested")
    }
  }

  func requested(at index: Int) -> XCTestExpectation {
    requestedExpectations[index]
  }

  func next() -> Date {
    lock.withLock {
      let index = nextIndex
      nextIndex += 1
      requestedExpectations[index].fulfill()
      return dates[index]
    }
  }
}

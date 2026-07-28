import Foundation
import XCTest

@testable import Bruce

final class ControlledEVChargingClient:
  HomeAssistantEVCharging, @unchecked Sendable
{
  private let lock = NSLock()
  private let loadStartedExpectations: [XCTestExpectation]
  private let setStartedExpectations: [XCTestExpectation]
  private let setFinishedExpectations: [XCTestExpectation]
  private var nextLoadRequest = 0
  private var nextSetRequest = 0
  private var loadContinuations:
    [Int: CheckedContinuation<HomeAssistantEVChargingSnapshot, any Error>] = [:]
  private var setContinuations: [Int: CheckedContinuation<HomeAssistantEVChargingMode, any Error>] =
    [:]

  init(loadRequestCount: Int = 0, setRequestCount: Int = 0) {
    loadStartedExpectations = (0..<loadRequestCount).map {
      XCTestExpectation(description: "EV charging load \($0) started")
    }
    setStartedExpectations = (0..<setRequestCount).map {
      XCTestExpectation(description: "EV charging change \($0) started")
    }
    setFinishedExpectations = (0..<setRequestCount).map {
      XCTestExpectation(description: "EV charging change \($0) finished")
    }
  }

  func loadStarted(at index: Int) -> XCTestExpectation {
    loadStartedExpectations[index]
  }

  func setStarted(at index: Int) -> XCTestExpectation {
    setStartedExpectations[index]
  }

  func setFinished(at index: Int) -> XCTestExpectation {
    setFinishedExpectations[index]
  }

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    try await loadSnapshot().mode
  }

  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    try await loadSnapshot()
  }

  private func loadSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    try await withCheckedThrowingContinuation { continuation in
      let request = lock.withLock {
        let request = nextLoadRequest
        nextLoadRequest += 1
        loadContinuations[request] = continuation
        return request
      }
      loadStartedExpectations[request].fulfill()
    }
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    let request = lock.withLock {
      let request = nextSetRequest
      nextSetRequest += 1
      return request
    }
    defer {
      setFinishedExpectations[request].fulfill()
    }
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        setContinuations[request] = continuation
      }
      setStartedExpectations[request].fulfill()
    }
  }

  func succeedLoad(
    _ request: Int,
    with mode: HomeAssistantEVChargingMode,
    activity: HomeAssistantEVChargingActivity = .unavailable
  ) {
    let continuation = lock.withLock {
      loadContinuations.removeValue(forKey: request)
    }
    continuation?.resume(
      returning: HomeAssistantEVChargingSnapshot(mode: mode, activity: activity)
    )
  }

  func succeedSet(_ request: Int, with mode: HomeAssistantEVChargingMode) {
    let continuation = lock.withLock {
      setContinuations.removeValue(forKey: request)
    }
    continuation?.resume(returning: mode)
  }
}

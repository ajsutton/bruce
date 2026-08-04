import Foundation
import XCTest

@testable import Bruce

final class StreamingEVChargingClient:
  HomeAssistantEVCharging, @unchecked Sendable
{
  let providesContinuousUpdates = true

  let started = XCTestExpectation(description: "EV charging stream started")
  let setStarted = XCTestExpectation(description: "EV charging mode change started")
  let loadStarted = XCTestExpectation(description: "EV charging reconciliation started")

  private let lock = NSLock()
  private var continuation: HomeAssistantEVChargingUpdateStream.Continuation?
  private var setContinuation: CheckedContinuation<HomeAssistantEVChargingMode, any Error>?
  private var loadContinuation: CheckedContinuation<HomeAssistantEVChargingSnapshot, any Error>?
  private var nextStreamStart: XCTestExpectation?

  func evChargingUpdates() -> HomeAssistantEVChargingUpdateStream {
    HomeAssistantEVChargingUpdateStream { continuation in
      let nextStreamStart = lock.withLock {
        self.continuation = continuation
        let expectation = self.nextStreamStart
        self.nextStreamStart = nil
        return expectation
      }
      started.fulfill()
      nextStreamStart?.fulfill()
    }
  }

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw StreamingEVChargingError.unexpectedRequest
  }

  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    loadStarted.fulfill()
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        loadContinuation = continuation
      }
    }
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    setStarted.fulfill()
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        setContinuation = continuation
      }
    }
  }

  func yield(_ update: HomeAssistantEVChargingUpdate) {
    let continuation = lock.withLock { self.continuation }
    continuation?.yield(update)
  }

  func finishUpdates() {
    let continuation = lock.withLock { self.continuation }
    continuation?.finish()
  }

  func expectNextStreamStart() -> XCTestExpectation {
    let expectation = XCTestExpectation(description: "EV charging stream restarted")
    lock.withLock {
      nextStreamStart = expectation
    }
    return expectation
  }

  func succeedSet(with mode: HomeAssistantEVChargingMode) {
    let continuation = lock.withLock {
      let continuation = setContinuation
      setContinuation = nil
      return continuation
    }
    continuation?.resume(returning: mode)
  }

  func failSet() {
    let continuation = lock.withLock {
      let continuation = setContinuation
      setContinuation = nil
      return continuation
    }
    continuation?.resume(throwing: StreamingEVChargingError.unexpectedRequest)
  }

  func succeedLoad(with snapshot: HomeAssistantEVChargingSnapshot) {
    let continuation = lock.withLock {
      let continuation = loadContinuation
      loadContinuation = nil
      return continuation
    }
    continuation?.resume(returning: snapshot)
  }
}

private enum StreamingEVChargingError: Error {
  case unexpectedRequest
}

func decision(desired: Bool) -> HomeAssistantEVChargingDecision {
  HomeAssistantEVChargingDecision(
    isChargingDesired: desired,
    overnightSafeChargingMinutes: 48,
    priceAllowsCharging: true,
    currentPriceDollarsPerKilowattHour: 0.24,
    batteryStateOfCharge: 78
  )
}

func snapshot(
  activity: HomeAssistantEVChargingActivity
) -> HomeAssistantEVChargingSnapshot {
  HomeAssistantEVChargingSnapshot(
    mode: .smart,
    activity: activity,
    decision: decision(desired: true)
  )
}

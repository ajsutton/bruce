import Foundation
import XCTest

@testable import Bruce

enum LifecycleTestSupport {}

final class ObservationTestTemperatureLoader:
  HomeAssistantTemperatureLoading, @unchecked Sendable
{
  let providesContinuousTemperatureUpdates = true
  let started = XCTestExpectation(description: "Temperature observation started")
  let cancelled = XCTestExpectation(description: "Temperature observation cancelled")
  private let lock = NSLock()
  private var storedStartCount = 0
  private var startExpectations: [Int: XCTestExpectation] = [:]

  var startCount: Int {
    lock.withLock { storedStartCount }
  }

  func expectStartCount(_ count: Int) -> XCTestExpectation {
    let expectation = XCTestExpectation(
      description: "Temperature observation reached \(count) starts"
    )
    let reached = lock.withLock {
      if storedStartCount >= count { return true }
      startExpectations[count] = expectation
      return false
    }
    if reached {
      expectation.fulfill()
    }
    return expectation
  }

  func removeStartExpectation(for count: Int) {
    lock.withLock {
      startExpectations[count] = nil
    }
  }

  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      let expectation = lock.withLock {
        storedStartCount += 1
        return startExpectations.removeValue(forKey: storedStartCount)
      }
      started.fulfill()
      expectation?.fulfill()
      continuation.onTermination = { _ in
        self.cancelled.fulfill()
      }
    }
  }
}

final class ControlledStateFeedRefresh: @unchecked Sendable {
  let started = XCTestExpectation(description: "State feed refresh started")
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Bool, Never>?

  func call() async -> Bool {
    started.fulfill()
    return await withCheckedContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
    }
  }

  func resume() {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(returning: false)
  }
}

final class ControlledStateFeedReset: @unchecked Sendable {
  let started = XCTestExpectation(description: "State feed reset started")
  private let blockingCall: Int
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var callCount = 0

  init(blockingCall: Int = 1) {
    self.blockingCall = blockingCall
  }

  func call() async {
    let shouldBlock = lock.withLock {
      callCount += 1
      return callCount == blockingCall
    }
    guard shouldBlock else { return }
    await withCheckedContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func resume() {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume()
  }
}

struct ObservationTestChargingClient: HomeAssistantEVCharging {
  let providesContinuousUpdates = true

  func evChargingUpdates() -> HomeAssistantEVChargingUpdateStream {
    HomeAssistantEVChargingUpdateStream { _ in }
  }

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw LifecycleObservationError.unexpectedRequest
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    throw LifecycleObservationError.unexpectedRequest
  }
}

struct ObservationTestEnergyLoader: HomeAssistantHomeEnergyLoading {
  let providesContinuousEnergyUpdates = true

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw LifecycleObservationError.unexpectedRequest
  }

  func homeEnergyUpdates() -> HomeAssistantHomeEnergyUpdateStream {
    HomeAssistantHomeEnergyUpdateStream { _ in }
  }
}

private enum LifecycleObservationError: Error {
  case unexpectedRequest
}

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

final class LifecycleHistoryLoader:
  HomeAssistantHomeEnergyLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private let requestDelay: ControlledHomeEnergyDelay?
  private var storedRequestCount = 0
  private var storedCancellationCount = 0
  private var requestExpectations: [Int: XCTestExpectation] = [:]
  private var cancellationExpectations: [Int: XCTestExpectation] = [:]

  init(blocksRequests: Bool = false) {
    requestDelay =
      blocksRequests
      ? ControlledHomeEnergyDelay(delayCount: 3)
      : nil
  }

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func expectRequestCount(_ count: Int) -> XCTestExpectation {
    let expectation = XCTestExpectation(
      description: "Energy history reached \(count) requests"
    )
    let reached = lock.withLock {
      if storedRequestCount >= count { return true }
      requestExpectations[count] = expectation
      return false
    }
    if reached {
      expectation.fulfill()
    }
    return expectation
  }

  func expectCancellationCount(_ count: Int) -> XCTestExpectation {
    let expectation = XCTestExpectation(
      description: "Energy history reached \(count) cancellations"
    )
    let reached = lock.withLock {
      if storedCancellationCount >= count { return true }
      cancellationExpectations[count] = expectation
      return false
    }
    if reached {
      expectation.fulfill()
    }
    return expectation
  }

  func loadHomeEnergyFlowHistory() async throws -> HomeEnergyFlowHistory {
    recordRequest()
    try await blockIfNeeded()
    let timestamp = Date(timeIntervalSince1970: 10_000)
    return HomeEnergyFlowHistory(
      interval: DateInterval(start: timestamp, duration: 60),
      readings: HomeEnergyFlowHistory.Series.allCases.map {
        HomeEnergyFlowHistory.Reading(
          series: $0,
          timestamp: timestamp,
          kilowatts: 1
        )
      }
    )
  }

  func loadHomeEnergyBatteryHistory() async throws -> HomeEnergyBatteryHistory {
    recordRequest()
    try await blockIfNeeded()
    let timestamp = Date(timeIntervalSince1970: 10_000)
    return HomeEnergyBatteryHistory(
      interval: DateInterval(start: timestamp, duration: 60),
      readings: [.init(timestamp: timestamp, stateOfCharge: 50)]
    )
  }

  func loadHomeEnergyPriceHistory() async throws -> HomeEnergyPriceHistory {
    recordRequest()
    try await blockIfNeeded()
    let timestamp = Date(timeIntervalSince1970: 10_000)
    return HomeEnergyPriceHistory(
      interval: DateInterval(start: timestamp, duration: 60),
      readings: HomeEnergyPriceHistory.Tariff.allCases.map {
        HomeEnergyPriceHistory.Reading(
          tariff: $0,
          timestamp: timestamp,
          dollarsPerKilowattHour: 0.2
        )
      }
    )
  }

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }

  private func recordRequest() {
    let expectation = lock.withLock {
      storedRequestCount += 1
      return requestExpectations.removeValue(forKey: storedRequestCount)
    }
    expectation?.fulfill()
  }

  private func blockIfNeeded() async throws {
    guard let requestDelay else { return }
    do {
      try await requestDelay.sleep(.zero)
    } catch {
      recordCancellation()
      throw error
    }
  }

  private func recordCancellation() {
    let expectation = lock.withLock {
      storedCancellationCount += 1
      return cancellationExpectations.removeValue(forKey: storedCancellationCount)
    }
    expectation?.fulfill()
  }
}

final class LifecycleDateSequence: @unchecked Sendable {
  private let lock = NSLock()
  private var dates: [Date]

  init(_ dates: [Date]) {
    self.dates = dates
  }

  func next() -> Date {
    lock.withLock { dates.removeFirst() }
  }
}

final class LifecycleClock: @unchecked Sendable {
  private let lock = NSLock()
  private var storedNow: Date

  init(now: Date) {
    storedNow = now
  }

  func callAsFunction() -> Date {
    lock.withLock { storedNow }
  }

  func advance(by interval: TimeInterval) {
    lock.withLock {
      storedNow = storedNow.addingTimeInterval(interval)
    }
  }
}

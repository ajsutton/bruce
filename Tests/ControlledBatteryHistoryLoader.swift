import Foundation
import XCTest

@testable import Bruce

final class ControlledBatteryHistoryLoader:
  HomeAssistantHomeEnergyLoading, @unchecked Sendable
{
  typealias Update = HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>

  let updateStreamStarted = XCTestExpectation(
    description: "Home energy update stream started"
  )
  let providesContinuousEnergyUpdates: Bool

  private let lock = NSLock()
  private let batteryStartedExpectations: [XCTestExpectation]
  private let batteryFinishedExpectations: [XCTestExpectation]
  private let priceStartedExpectations: [XCTestExpectation]
  private let priceFinishedExpectations: [XCTestExpectation]
  private var nextBatteryRequest = 0
  private var nextPriceRequest = 0
  private var batteryContinuations:
    [Int: CheckedContinuation<HomeEnergyBatteryHistory, any Error>] = [:]
  private var priceContinuations: [Int: CheckedContinuation<HomeEnergyPriceHistory, any Error>] =
    [:]
  private var updateContinuation: AsyncThrowingStream<Update, any Error>.Continuation?

  init(
    batteryRequestCount: Int,
    priceRequestCount: Int = 0,
    providesContinuousEnergyUpdates: Bool = false
  ) {
    batteryStartedExpectations = Self.expectations(
      count: batteryRequestCount,
      description: "Battery history load"
    )
    batteryFinishedExpectations = Self.expectations(
      count: batteryRequestCount,
      description: "Battery history finish"
    )
    priceStartedExpectations = Self.expectations(
      count: priceRequestCount,
      description: "Price history load"
    )
    priceFinishedExpectations = Self.expectations(
      count: priceRequestCount,
      description: "Price history finish"
    )
    self.providesContinuousEnergyUpdates = providesContinuousEnergyUpdates
  }

  func batteryStarted(at index: Int) -> XCTestExpectation {
    batteryStartedExpectations[index]
  }

  func batteryFinished(at index: Int) -> XCTestExpectation {
    batteryFinishedExpectations[index]
  }

  func priceStarted(at index: Int) -> XCTestExpectation {
    priceStartedExpectations[index]
  }

  func priceFinished(at index: Int) -> XCTestExpectation {
    priceFinishedExpectations[index]
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

  func loadHomeEnergyBatteryHistory() async throws -> HomeEnergyBatteryHistory {
    let request = lock.withLock {
      defer { nextBatteryRequest += 1 }
      return nextBatteryRequest
    }
    defer {
      batteryFinishedExpectations[request].fulfill()
    }
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        batteryContinuations[request] = continuation
      }
      batteryStartedExpectations[request].fulfill()
    }
  }

  func loadHomeEnergyPriceHistory() async throws -> HomeEnergyPriceHistory {
    guard !priceStartedExpectations.isEmpty else { return .empty }
    let request = lock.withLock {
      defer { nextPriceRequest += 1 }
      return nextPriceRequest
    }
    defer {
      priceFinishedExpectations[request].fulfill()
    }
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        priceContinuations[request] = continuation
      }
      priceStartedExpectations[request].fulfill()
    }
  }

  func yield(_ update: Update) {
    lock.withLock { updateContinuation }?.yield(update)
  }

  func finishUpdates() {
    let continuation = lock.withLock {
      defer { updateContinuation = nil }
      return updateContinuation
    }
    continuation?.finish()
  }

  func succeedBattery(_ request: Int, with history: HomeEnergyBatteryHistory) {
    takeBatteryContinuation(request)?.resume(returning: history)
  }

  func failBattery(_ request: Int, with error: any Error) {
    takeBatteryContinuation(request)?.resume(throwing: error)
  }

  func succeedPrice(_ request: Int, with history: HomeEnergyPriceHistory) {
    takePriceContinuation(request)?.resume(returning: history)
  }

  private func takeBatteryContinuation(
    _ request: Int
  ) -> CheckedContinuation<HomeEnergyBatteryHistory, any Error>? {
    lock.withLock {
      batteryContinuations.removeValue(forKey: request)
    }
  }

  private func takePriceContinuation(
    _ request: Int
  ) -> CheckedContinuation<HomeEnergyPriceHistory, any Error>? {
    lock.withLock {
      priceContinuations.removeValue(forKey: request)
    }
  }

  private static func expectations(
    count: Int,
    description: String
  ) -> [XCTestExpectation] {
    (0..<count).map {
      XCTestExpectation(description: "\(description) \($0)")
    }
  }
}

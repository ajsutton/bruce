import XCTest

@testable import Bruce

final class RecordingConnectionSupervisor:
  HomeAssistantConnectionSupervising, @unchecked Sendable
{
  let readinessStarted = XCTestExpectation(description: "Shared feed readiness requested")
  let stopStarted = XCTestExpectation(description: "Supervisor stop started")
  private let lock = NSLock()
  private let blocksReadiness: Bool
  private let blocksStop: Bool
  private let readinessError: (any Error)?
  private var readinessContinuation: CheckedContinuation<Void, any Error>?
  private var stopContinuation: CheckedContinuation<Void, Never>?
  private var storedReadinessRequestCount = 0
  private var didBlockStop = false

  init(
    blocksReadiness: Bool = false,
    blocksStop: Bool = false,
    readinessError: (any Error)? = nil
  ) {
    self.blocksReadiness = blocksReadiness
    self.blocksStop = blocksStop
    self.readinessError = readinessError
  }

  var readinessRequestCount: Int { lock.withLock { storedReadinessRequestCount } }

  func requireFreshLiveData() async throws {
    lock.withLock { storedReadinessRequestCount += 1 }
    readinessStarted.fulfill()
    if let readinessError { throw readinessError }
    guard blocksReadiness else { return }
    try await withCheckedThrowingContinuation { continuation in
      lock.withLock { readinessContinuation = continuation }
    }
  }

  func completeReadiness() {
    let continuation = lock.withLock {
      defer { readinessContinuation = nil }
      return readinessContinuation
    }
    continuation?.resume()
  }

  func stop() async {
    stopStarted.fulfill()
    let shouldBlock = lock.withLock {
      guard blocksStop, !didBlockStop else { return false }
      didBlockStop = true
      return true
    }
    guard shouldBlock else { return }
    await withCheckedContinuation { continuation in
      lock.withLock { stopContinuation = continuation }
    }
  }

  func prepareForDisconnect() async -> UUID {
    await stop()
    return UUID()
  }

  func recoverFromFailedDisconnect(preparationID: UUID) async {}

  func completeStop() {
    let continuation = lock.withLock {
      defer { stopContinuation = nil }
      return stopContinuation
    }
    continuation?.resume()
  }
}

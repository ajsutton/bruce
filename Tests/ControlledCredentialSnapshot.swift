import XCTest

@testable import Bruce

final class ControlledCredentialSnapshot: @unchecked Sendable {
  let started = XCTestExpectation(description: "Credential snapshot started")
  private let lock = NSLock()
  private let snapshot = HomeAssistantCredentialSnapshot(
    authenticationSessionEpoch: 1,
    persistenceGeneration: 1,
    availability: .ready
  )
  private var continuation: CheckedContinuation<HomeAssistantCredentialSnapshot, Never>?

  func load() async -> HomeAssistantCredentialSnapshot {
    await withCheckedContinuation { continuation in
      lock.withLock { self.continuation = continuation }
      started.fulfill()
    }
  }

  func resume() {
    let continuation = lock.withLock {
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume(returning: snapshot)
  }
}

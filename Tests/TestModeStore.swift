import Combine
import XCTest

@testable import Bruce

@MainActor
final class TestModeStore: BruceModeStoring {
  var localMode: BruceMode?
  var syncedMode: BruceMode?
  private let syncedPreferenceSubject = PassthroughSubject<Void, Never>()
  private var hasUnpublishedLocalChangeValue: Bool
  private(set) var didPrepareForSynchronization = false
  private let eventRecorder: TestEventRecorder?

  init(
    localMode: BruceMode? = nil,
    syncedMode: BruceMode? = nil,
    hasUnpublishedLocalChange: Bool = false,
    eventRecorder: TestEventRecorder? = nil
  ) {
    self.localMode = localMode
    self.syncedMode = syncedMode
    hasUnpublishedLocalChangeValue = hasUnpublishedLocalChange
    self.eventRecorder = eventRecorder
  }

  var syncedPreferenceChanges: AnyPublisher<Void, Never> {
    syncedPreferenceSubject.eraseToAnyPublisher()
  }

  func prepareForSynchronization() {
    didPrepareForSynchronization = true
  }

  func hasUnpublishedLocalChange() -> Bool {
    hasUnpublishedLocalChangeValue
  }

  func loadLocalMode() -> BruceMode? {
    localMode
  }

  func loadSyncedMode() -> BruceMode? {
    syncedMode
  }

  func saveLocalMode(_ mode: BruceMode) {
    localMode = mode
    hasUnpublishedLocalChangeValue = false
  }

  func saveMode(_ mode: BruceMode) {
    eventRecorder?.events.append(.saveMode(mode))
    localMode = mode
    syncedMode = mode
    hasUnpublishedLocalChangeValue = false
  }

  func sendSyncedPreferenceChange() {
    syncedPreferenceSubject.send()
  }

  func setLocalModeFromSystemSettings(_ mode: BruceMode) {
    localMode = mode
    hasUnpublishedLocalChangeValue = true
  }
}

@MainActor
final class TestUbiquitousStore: UbiquitousKeyValueStoring {
  private var values: [String: Any] = [:]

  func object(forKey key: String) -> Any? {
    values[key]
  }

  func set(_ value: Any?, forKey key: String) {
    values[key] = value
  }

  func synchronize() -> Bool {
    true
  }
}

@MainActor
final class TestIconApplier: AppIconApplying {
  private(set) var appliedModes: [BruceMode] = []
  private let failingMode: BruceMode?
  private let error: TestIconError
  private let eventRecorder: TestEventRecorder?

  init(
    failingMode: BruceMode? = nil,
    error: TestIconError = .unavailable,
    eventRecorder: TestEventRecorder? = nil
  ) {
    self.failingMode = failingMode
    self.error = error
    self.eventRecorder = eventRecorder
  }

  func apply(_ mode: BruceMode) async throws {
    appliedModes.append(mode)
    eventRecorder?.events.append(.applyIcon(mode))
    if mode == failingMode {
      throw error
    }
  }
}

enum TestIconError: Error {
  case unavailable
  case unsupported
}

@MainActor
final class CancellingOnceIconApplier: AppIconApplying {
  private(set) var attemptCount = 0

  func apply(_ mode: BruceMode) async throws {
    attemptCount += 1
    if attemptCount == 1 {
      throw CancellationError()
    }
  }
}

@MainActor
final class SuspendingIconApplier: AppIconApplying {
  private(set) var appliedModes: [BruceMode] = []
  private let suspendingMode: BruceMode
  private let didSuspend: XCTestExpectation
  private var shouldSuspend = true
  private var applyContinuation: CheckedContinuation<Void, Never>?

  init(suspendingMode: BruceMode, didSuspend: XCTestExpectation) {
    self.suspendingMode = suspendingMode
    self.didSuspend = didSuspend
  }

  func apply(_ mode: BruceMode) async throws {
    appliedModes.append(mode)
    guard mode == suspendingMode, shouldSuspend else {
      return
    }
    shouldSuspend = false
    await withCheckedContinuation { continuation in
      applyContinuation = continuation
      didSuspend.fulfill()
    }
  }

  func resume() {
    applyContinuation?.resume()
    applyContinuation = nil
  }
}

final class TestEventRecorder {
  var events: [TestEvent] = []
}

enum TestEvent: Equatable {
  case applyIcon(BruceMode)
  case saveMode(BruceMode)
}

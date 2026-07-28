import Combine
import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantEVChargingTimingTests: XCTestCase {
  func testSlowModeChangeShowsDelayedProgressWithoutChangingOptimisticState() async {
    let client = ControlledEVChargingClient(setRequestCount: 1)
    let progressDelay = ControlledEVChargingDelay(description: "Progress delay started")
    let timeoutDelay = ControlledEVChargingDelay(description: "Timeout delay started")
    let store = HomeAssistantEVChargingStore(
      client: client,
      mode: .off,
      progressSleep: progressDelay.sleep,
      timeoutSleep: timeoutDelay.sleep
    )
    let progressShown = expectation(description: "Delayed progress shown")
    let subscription = store.$showsProgress.dropFirst().sink { showsProgress in
      if showsProgress {
        progressShown.fulfill()
      }
    }
    let change = Task {
      await store.selectMode(.charging)
    }
    await waitForModeChangeStart(
      client: client,
      progressDelay: progressDelay,
      timeoutDelay: timeoutDelay
    )

    XCTAssertEqual(store.mode, .charging)
    XCTAssertFalse(store.showsProgress)

    progressDelay.finish()
    await fulfillment(of: [progressShown], timeout: 1)

    XCTAssertEqual(store.mode, .charging)
    client.succeedSet(0, with: .charging)
    await change.value
    XCTAssertFalse(store.showsProgress)
    withExtendedLifetime(subscription) {}
  }

  func testModeChangeTimeoutRollsBackAndRejectsLateSuccess() async {
    let client = ControlledEVChargingClient(loadRequestCount: 2, setRequestCount: 1)
    let progressDelay = ControlledEVChargingDelay(description: "Progress delay started")
    let timeoutDelay = ControlledEVChargingDelay(description: "Timeout delay started")
    let store = HomeAssistantEVChargingStore(
      client: client,
      mode: .off,
      progressSleep: progressDelay.sleep,
      timeoutSleep: timeoutDelay.sleep
    )
    let timedOut = expectation(description: "Mode change timed out")
    let subscription = store.$problem.compactMap(\.self).sink { problem in
      if problem == .updateTimedOut {
        timedOut.fulfill()
      }
    }
    let change = Task {
      await store.selectMode(.charging)
    }
    await waitForModeChangeStart(
      client: client,
      progressDelay: progressDelay,
      timeoutDelay: timeoutDelay
    )

    XCTAssertEqual(store.mode, .charging)
    timeoutDelay.finish()
    await fulfillment(of: [timedOut], timeout: 1)

    assertTimedOut(store)
    await change.value

    let refresh = Task {
      await store.load()
    }
    await fulfillment(of: [client.loadStarted(at: 0)], timeout: 1)
    client.succeedLoad(0, with: .off)
    await refresh.value

    XCTAssertEqual(store.mode, .off)
    XCTAssertTrue(store.isLive)

    let reconciled = expectation(description: "Late mode change reconciled")
    let reconciliationSubscription = store.$mode.dropFirst().sink { mode in
      if mode == .charging {
        reconciled.fulfill()
      }
    }
    client.succeedSet(0, with: .charging)
    await fulfillment(of: [client.loadStarted(at: 1)], timeout: 1)
    client.succeedLoad(1, with: .charging)
    await fulfillment(of: [reconciled], timeout: 1)

    XCTAssertEqual(store.mode, .charging)
    XCTAssertTrue(store.isLive)
    XCTAssertNil(store.problem)
    withExtendedLifetime((subscription, reconciliationSubscription)) {}
  }

  func testAutomaticTimeoutReconciliationPreservesTimeoutError() async {
    let client = ControlledEVChargingClient(loadRequestCount: 1, setRequestCount: 1)
    let progressDelay = ControlledEVChargingDelay(description: "Progress delay started")
    let timeoutDelay = ControlledEVChargingDelay(description: "Timeout delay started")
    let store = HomeAssistantEVChargingStore(
      client: client,
      mode: .off,
      progressSleep: progressDelay.sleep,
      timeoutSleep: timeoutDelay.sleep
    )
    let change = Task {
      await store.selectMode(.charging)
    }
    await waitForModeChangeStart(
      client: client,
      progressDelay: progressDelay,
      timeoutDelay: timeoutDelay
    )

    timeoutDelay.finish()
    await change.value
    let reconciled = expectation(description: "Timed-out change reconciled")
    let subscription = store.$isLive.dropFirst().filter { $0 }.prefix(1).sink { _ in
      reconciled.fulfill()
    }
    client.succeedSet(0, with: .charging)
    await fulfillment(of: [client.loadStarted(at: 0)], timeout: 1)

    XCTAssertEqual(store.mode, .off)
    XCTAssertTrue(store.isLoading)
    XCTAssertFalse(store.isLive)

    client.succeedLoad(0, with: .off)
    await fulfillment(of: [reconciled], timeout: 1)

    XCTAssertEqual(store.mode, .off)
    XCTAssertTrue(store.isLive)
    XCTAssertEqual(store.problem, .updateTimedOut)
    withExtendedLifetime(subscription) {}
  }

  func testFastModeChangeNeverShowsProgressAfterDelayCancellation() async {
    let client = ControlledEVChargingClient(setRequestCount: 1)
    let progressDelay = ControlledEVChargingDelay(description: "Progress delay started")
    let timeoutDelay = ControlledEVChargingDelay(description: "Timeout delay started")
    let store = HomeAssistantEVChargingStore(
      client: client,
      mode: .off,
      progressSleep: progressDelay.sleep,
      timeoutSleep: timeoutDelay.sleep
    )
    let change = Task {
      await store.selectMode(.charging)
    }
    await waitForModeChangeStart(
      client: client,
      progressDelay: progressDelay,
      timeoutDelay: timeoutDelay
    )

    client.succeedSet(0, with: .charging)
    await change.value
    await fulfillment(of: [progressDelay.completed], timeout: 1)
    progressDelay.finish()

    XCTAssertFalse(store.showsProgress)
    XCTAssertEqual(store.mode, .charging)
  }

  func testCancellationReconciliationAcceptsDefaultSnapshotWithoutOrderingTimestamp() async {
    let store = HomeAssistantEVChargingStore(
      client: ConfirmationCancelledEVChargingClient(),
      mode: .off
    )
    let reconciled = expectation(description: "Cancelled confirmation reconciled")
    let subscription = store.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in
      reconciled.fulfill()
    }

    await store.selectMode(.charging)
    await fulfillment(of: [reconciled], timeout: 1)

    XCTAssertEqual(store.mode, .charging)
    XCTAssertFalse(store.isChanging)
    XCTAssertTrue(store.isLive)
    XCTAssertTrue(store.canSelectMode)
    XCTAssertNil(store.problem)
    withExtendedLifetime(subscription) {}
  }

  func testFailedCancellationReconciliationOffersRecovery() async {
    let store = HomeAssistantEVChargingStore(
      client: FailedCancellationReconciliationClient(),
      mode: .off
    )
    let problemPublished = expectation(description: "Reconciliation problem published")
    let subscription = store.$problem.compactMap(\.self).prefix(1).sink { _ in
      problemPublished.fulfill()
    }

    await store.selectMode(.charging)
    await fulfillment(of: [problemPublished], timeout: 1)

    XCTAssertEqual(store.mode, .off)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.canSelectMode)
    XCTAssertEqual(store.problem, .connectionUnavailable)
    withExtendedLifetime(subscription) {}
  }

  func testCancelledReconciliationOffersRecovery() async {
    let store = HomeAssistantEVChargingStore(
      client: CancelledReconciliationClient(),
      mode: .off
    )
    let problemPublished = expectation(description: "Cancelled reconciliation problem published")
    let subscription = store.$problem.compactMap(\.self).prefix(1).sink { _ in
      problemPublished.fulfill()
    }

    await store.selectMode(.charging)
    await fulfillment(of: [problemPublished], timeout: 1)

    XCTAssertEqual(store.mode, .off)
    XCTAssertFalse(store.isLive)
    XCTAssertEqual(store.problem, .invalidResponse)
    withExtendedLifetime(subscription) {}
  }

  func testNonCompletingReconciliationDoesNotRetainStore() async {
    let client = ControlledEVChargingClient(loadRequestCount: 1, setRequestCount: 1)
    var store: HomeAssistantEVChargingStore? = HomeAssistantEVChargingStore(
      client: client,
      mode: .off
    )
    weak let weakStore = store
    let change = Task {
      await store?.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted(at: 0)], timeout: 1)

    change.cancel()
    await change.value
    client.succeedSet(0, with: .charging)
    await fulfillment(of: [client.loadStarted(at: 0)], timeout: 1)

    store = nil

    XCTAssertNil(weakStore)
    client.succeedLoad(0, with: .charging)
  }

  private func waitForModeChangeStart(
    client: ControlledEVChargingClient,
    progressDelay: ControlledEVChargingDelay,
    timeoutDelay: ControlledEVChargingDelay
  ) async {
    await fulfillment(
      of: [
        client.setStarted(at: 0),
        progressDelay.started,
        timeoutDelay.started,
      ],
      timeout: 1
    )
  }

  private func assertTimedOut(_ store: HomeAssistantEVChargingStore) {
    XCTAssertEqual(store.mode, .off)
    XCTAssertFalse(store.isChanging)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.showsProgress)
    XCTAssertEqual(store.problem, .updateTimedOut)
  }

}

private actor ConfirmationCancelledEVChargingClient: HomeAssistantEVCharging {
  private var serverMode = HomeAssistantEVChargingMode.off

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    serverMode
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    serverMode = mode
    throw CancellationError()
  }
}

private actor FailedCancellationReconciliationClient: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw URLError(.notConnectedToInternet)
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    throw CancellationError()
  }
}

private actor CancelledReconciliationClient: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw CancellationError()
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    throw CancellationError()
  }
}

private final class ControlledEVChargingDelay: @unchecked Sendable {
  let started: XCTestExpectation
  let completed: XCTestExpectation

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var shouldFinish = false

  init(description: String) {
    started = XCTestExpectation(description: description)
    completed = XCTestExpectation(description: "\(description) completed")
  }

  func sleep(_: Duration) async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let finishesImmediately = lock.withLock {
          if shouldFinish {
            return true
          }
          self.continuation = continuation
          return false
        }
        started.fulfill()
        if finishesImmediately {
          continuation.resume()
        }
      }
    } onCancel: {
      finish()
    }
    completed.fulfill()
  }

  func finish() {
    let continuation = lock.withLock {
      shouldFinish = true
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume()
  }
}

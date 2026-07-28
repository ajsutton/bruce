import Foundation
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantEVChargingStoreTests: XCTestCase {
  func testSuccessfulLoadPublishesCurrentMode() async {
    let client = RecordingEVChargingClient(loadResults: [.success(.smart)])
    let store = HomeAssistantEVChargingStore(client: client)

    await store.load()

    XCTAssertEqual(store.mode, .smart)
    XCTAssertTrue(store.isLive)
    XCTAssertFalse(store.isLoading)
    XCTAssertNil(store.problem)
  }

  func testSuccessfulModeChangeKeepsTheOptimisticMode() async {
    let client = RecordingEVChargingClient(
      loadResults: [],
      setResults: [.success(.charging)]
    )
    let store = HomeAssistantEVChargingStore(client: client, mode: .off)

    await store.selectMode(.charging)
    let requestedModes = await client.requestedModes

    XCTAssertEqual(requestedModes, [.charging])
    XCTAssertEqual(store.mode, .charging)
    XCTAssertTrue(store.isLive)
    XCTAssertFalse(store.isChanging)
    XCTAssertFalse(store.showsProgress)
    XCTAssertNil(store.problem)
  }

  func testSelectingModePublishesOptimisticModeBeforeConfirmation() async {
    let client = ControlledEVChargingClient(setRequestCount: 1)
    let store = HomeAssistantEVChargingStore(client: client, mode: .off)
    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted(at: 0)], timeout: 1)

    XCTAssertEqual(store.mode, .charging)
    XCTAssertTrue(store.isChanging)
    XCTAssertTrue(store.isLive)
    XCTAssertFalse(store.canSelectMode)

    client.succeedSet(0, with: .charging)
    await change.value
    XCTAssertTrue(store.canSelectMode)
  }

  func testFailedModeChangeKeepsTheConfirmedMode() async {
    let client = RecordingEVChargingClient(
      loadResults: [],
      setResults: [.failure(EVChargingTestError.failed)]
    )
    let store = HomeAssistantEVChargingStore(client: client, mode: .smart)

    await store.selectMode(.off)

    XCTAssertEqual(store.mode, .smart)
    XCTAssertFalse(store.isChanging)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.showsProgress)
    XCTAssertEqual(store.problem, .updateFailed)
  }

  func testMismatchedConfirmationPublishesConfirmedModeAndError() async {
    let client = RecordingEVChargingClient(
      loadResults: [],
      setResults: [.success(.smart)]
    )
    let store = HomeAssistantEVChargingStore(client: client, mode: .off)

    await store.selectMode(.charging)

    XCTAssertEqual(store.mode, .smart)
    XCTAssertTrue(store.isLive)
    XCTAssertEqual(store.problem, .updateFailed)
  }

  func testUnavailableConnectionKeepsModeButDisablesChanges() {
    let store = HomeAssistantEVChargingStore(
      client: RecordingEVChargingClient(loadResults: []),
      mode: .smart
    )

    store.markConnectionUnavailable()

    XCTAssertEqual(store.mode, .smart)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.canSelectMode)
    XCTAssertEqual(store.problem, .connectionNeedsManagement)
  }

  func testAuthenticationFailureRequestsRecoveryAndSurvivesUnavailableState() async {
    let recoveryRequested = expectation(description: "Authentication recovery requested")
    let store = HomeAssistantEVChargingStore(
      client: AuthenticationRequiredEVChargingClient(),
      onAuthenticationRequired: {
        recoveryRequested.fulfill()
      }
    )

    await store.load()
    await fulfillment(of: [recoveryRequested], timeout: 1)
    store.markConnectionUnavailable()

    XCTAssertEqual(store.problem, .signInRequired)
    XCTAssertFalse(store.isLive)
  }

  func testUnavailableConnectionRejectsLateLoadSuccess() async {
    let client = ControlledEVChargingClient(loadRequestCount: 1)
    let store = HomeAssistantEVChargingStore(client: client)
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [client.loadStarted(at: 0)], timeout: 1)

    store.markConnectionUnavailable()
    client.succeedLoad(0, with: .charging)
    await load.value

    XCTAssertNil(store.mode)
    XCTAssertFalse(store.isLive)
    XCTAssertEqual(store.problem, .connectionNeedsManagement)
  }

  func testNewerLoadRejectsLateResultFromOlderLoad() async {
    let client = ControlledEVChargingClient(loadRequestCount: 2)
    let store = HomeAssistantEVChargingStore(client: client)
    let firstLoad = Task {
      await store.load()
    }
    await fulfillment(of: [client.loadStarted(at: 0)], timeout: 1)
    let secondLoad = Task {
      await store.load()
    }
    await fulfillment(of: [client.loadStarted(at: 1)], timeout: 1)

    client.succeedLoad(1, with: .smart)
    await secondLoad.value
    client.succeedLoad(0, with: .charging)
    await firstLoad.value

    XCTAssertEqual(store.mode, .smart)
    XCTAssertTrue(store.isLive)
  }

  func testActiveCancellationDoesNotPublishLateLoad() async {
    let client = ControlledEVChargingClient(loadRequestCount: 1)
    let store = HomeAssistantEVChargingStore(client: client)
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [client.loadStarted(at: 0)], timeout: 1)

    load.cancel()
    client.succeedLoad(0, with: .charging)
    await load.value

    XCTAssertNil(store.mode)
    XCTAssertNil(store.problem)
    XCTAssertFalse(store.isLoading)
    XCTAssertFalse(store.isLive)
  }

  func testResetRejectsLateModeChangeSuccess() async {
    let client = ControlledEVChargingClient(setRequestCount: 1)
    let store = HomeAssistantEVChargingStore(client: client, mode: .off)
    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted(at: 0)], timeout: 1)

    store.reset()
    client.succeedSet(0, with: .charging)
    await change.value

    XCTAssertNil(store.mode)
    XCTAssertFalse(store.isLive)
    XCTAssertFalse(store.isChanging)
  }

  func testUnavailableConnectionRollsBackOptimisticModeAndRejectsLateSuccess() async {
    let client = ControlledEVChargingClient(setRequestCount: 1)
    let store = HomeAssistantEVChargingStore(client: client, mode: .off)
    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted(at: 0)], timeout: 1)

    store.markConnectionUnavailable()
    await change.value

    XCTAssertEqual(store.mode, .off)
    XCTAssertFalse(store.isChanging)
    XCTAssertFalse(store.isLive)
    XCTAssertEqual(store.problem, .connectionNeedsManagement)

    let lateModePublished = expectation(description: "Late mode change was not published")
    lateModePublished.isInverted = true
    let subscription = store.$mode.dropFirst().sink { _ in
      lateModePublished.fulfill()
    }
    client.succeedSet(0, with: .charging)
    await fulfillment(of: [client.setFinished(at: 0)], timeout: 1)
    await fulfillment(of: [lateModePublished], timeout: 0.1)

    XCTAssertEqual(store.mode, .off)
    XCTAssertEqual(store.problem, .connectionNeedsManagement)
    withExtendedLifetime(subscription) {}
  }

  func testActiveCancellationReconcilesARequestThatFinishesLate() async {
    let client = ControlledEVChargingClient(loadRequestCount: 2, setRequestCount: 1)
    let store = HomeAssistantEVChargingStore(client: client, mode: .off)
    let change = Task {
      await store.selectMode(.charging)
    }
    await fulfillment(of: [client.setStarted(at: 0)], timeout: 1)

    XCTAssertEqual(store.mode, .charging)
    XCTAssertTrue(store.isChanging)

    change.cancel()
    await change.value

    XCTAssertEqual(store.mode, .off)
    XCTAssertNil(store.problem)
    XCTAssertFalse(store.isChanging)
    XCTAssertFalse(store.isLive)

    let refresh = Task {
      await store.load()
    }
    await fulfillment(of: [client.loadStarted(at: 0)], timeout: 1)
    client.succeedLoad(0, with: .off)
    await refresh.value

    XCTAssertEqual(store.mode, .off)
    XCTAssertTrue(store.isLive)

    client.succeedSet(0, with: .charging)
    await fulfillment(of: [client.loadStarted(at: 1)], timeout: 1)
    let reconciled = expectation(description: "Cancelled mode change reconciled")
    let subscription = store.$mode.dropFirst().sink { mode in
      if mode == .charging {
        reconciled.fulfill()
      }
    }
    client.succeedLoad(1, with: .charging)
    await fulfillment(of: [client.setFinished(at: 0)], timeout: 1)
    await fulfillment(of: [reconciled], timeout: 1)

    XCTAssertEqual(store.mode, .charging)
    XCTAssertTrue(store.isLive)
    XCTAssertNil(store.problem)
    withExtendedLifetime(subscription) {}
  }

}

private enum EVChargingTestError: Error, Sendable {
  case failed
}

private actor RecordingEVChargingClient: HomeAssistantEVCharging {
  private var loadResults: [Result<HomeAssistantEVChargingMode, EVChargingTestError>]
  private var setResults: [Result<HomeAssistantEVChargingMode, EVChargingTestError>]
  private(set) var requestedModes: [HomeAssistantEVChargingMode] = []

  init(
    loadResults: [Result<HomeAssistantEVChargingMode, EVChargingTestError>],
    setResults: [Result<HomeAssistantEVChargingMode, EVChargingTestError>] = []
  ) {
    self.loadResults = loadResults
    self.setResults = setResults
  }

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    try loadResults.removeFirst().get()
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    requestedModes.append(mode)
    return try setResults.removeFirst().get()
  }
}

private struct AuthenticationRequiredEVChargingClient: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw HomeAssistantAPIError.reauthenticationRequired
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    throw HomeAssistantAPIError.reauthenticationRequired
  }
}

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
    [Int: CheckedContinuation<HomeAssistantEVChargingMode, any Error>] = [:]
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

  func succeedLoad(_ request: Int, with mode: HomeAssistantEVChargingMode) {
    let continuation = lock.withLock {
      loadContinuations.removeValue(forKey: request)
    }
    continuation?.resume(returning: mode)
  }

  func succeedSet(_ request: Int, with mode: HomeAssistantEVChargingMode) {
    let continuation = lock.withLock {
      setContinuations.removeValue(forKey: request)
    }
    continuation?.resume(returning: mode)
  }
}

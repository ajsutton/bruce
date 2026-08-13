import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantTemperatureStoreTests: XCTestCase {
  func testSuccessfulLoadPublishesReadingsAndCheckTime() async {
    let checkTime = Date(timeIntervalSince1970: 300)
    let readings = [
      reading(id: "first"),
      reading(id: "second"),
    ]
    let store = HomeAssistantTemperatureStore(
      loader: QueueTemperatureLoader(results: [.success(readings)]),
      now: { checkTime }
    )

    await store.load()

    XCTAssertEqual(store.readings, readings)
    XCTAssertEqual(store.lastChecked, checkTime)
    XCTAssertFalse(store.isLoading)
    XCTAssertNil(store.problem)
  }

  func testFailedRefreshKeepsPreviousReadingsAndReportsProblem() async {
    let originalReadings = [reading(id: "temperature")]
    let loader = QueueTemperatureLoader(
      results: [
        .success(originalReadings),
        .failure(.connectionUnavailable),
      ]
    )
    let store = HomeAssistantTemperatureStore(loader: loader)
    await store.load()

    await store.load()

    XCTAssertEqual(store.readings, originalReadings)
    XCTAssertEqual(store.problem, .connectionUnavailable)
    XCTAssertFalse(store.isLoading)
  }

  func testAuthenticationFailureMovesSetupToSignInRecovery() async {
    let credentials = credentials()
    let setupStore = HomeAssistantSetupStore(
      discovery: EmptyTemperatureDiscovery(),
      connection: RestoredTemperatureConnection(credentials: credentials)
    )
    await setupStore.restoreSavedConnection()
    let store = HomeAssistantTemperatureStore(
      loader: QueueTemperatureLoader(results: [.failure(.signInRequired)]),
      onAuthenticationRequired: {
        setupStore.requireReauthentication()
      }
    )

    await store.load()

    XCTAssertEqual(setupStore.step, .configured(credentials))
    XCTAssertEqual(setupStore.connectionCheckState, .reauthenticationRequired)
    XCTAssertEqual(store.problem, .signInRequired)
  }

  func testDisconnectedSynchronizationClearsLoadedState() async {
    let store = HomeAssistantTemperatureStore(
      loader: QueueTemperatureLoader(
        results: [.success([reading(id: "temperature")])]
      )
    )
    await store.load()

    await store.synchronize(with: .signedOut)

    XCTAssertTrue(store.readings.isEmpty)
    XCTAssertNil(store.lastChecked)
    XCTAssertNil(store.problem)
  }

  func testUnavailableConnectionRejectsLateSuccess() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let store = HomeAssistantTemperatureStore(loader: loader)
    let load = Task {
      await store.synchronize(with: .ready(credentials()))
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)

    await store.synchronize(with: .requiresUserAction)
    loader.succeedRequest(0, with: [reading(id: "late")])
    await load.value

    XCTAssertTrue(store.readings.isEmpty)
    XCTAssertNil(store.lastChecked)
  }

  func testNewerLoadRejectsLateResultFromOlderLoad() async {
    let loader = ControlledTemperatureLoader(requestCount: 2)
    let store = HomeAssistantTemperatureStore(loader: loader)
    let firstLoad = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    let secondLoad = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 1)], timeout: 1)

    let newest = [reading(id: "newest")]
    loader.succeedRequest(1, with: newest)
    await secondLoad.value
    loader.succeedRequest(0, with: [reading(id: "old")])
    await firstLoad.value

    XCTAssertEqual(store.readings, newest)
  }

  func testActiveCancellationWithURLCancellationDoesNotReportProblem() async {
    let loader = CancellingTemperatureLoader()
    let store = HomeAssistantTemperatureStore(loader: loader)
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started], timeout: 1)

    load.cancel()
    await load.value
    await fulfillment(of: [loader.cancelled], timeout: 1)

    XCTAssertNil(store.problem)
    XCTAssertFalse(store.isLoading)
  }

  func testReconnectKeepsReadingsAndClearsWarningAfterFreshSnapshot() async {
    let original = [reading(id: "original")]
    let refreshed = [reading(id: "refreshed")]
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let store = HomeAssistantTemperatureStore(loader: loader)
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    let warningPublished = expectation(description: "Reconnect warning published")
    let warningSubscription = store.$problem.compactMap(\.self).sink { problem in
      if problem == .reconnecting {
        warningPublished.fulfill()
      }
    }

    loader.yieldRequest(0, update: .live(original))
    loader.yieldRequest(0, update: .reconnecting(original))
    await fulfillment(of: [warningPublished], timeout: 1)

    XCTAssertEqual(store.readings, original)
    XCTAssertEqual(store.problem, .reconnecting)

    let refreshedReadingsPublished = expectation(description: "Fresh readings published")
    let readingsSubscription = store.$readings.dropFirst().sink { readings in
      if readings == refreshed {
        refreshedReadingsPublished.fulfill()
      }
    }
    loader.yieldRequest(0, update: .live(refreshed))
    await fulfillment(of: [refreshedReadingsPublished], timeout: 1)
    loader.finishRequest(0)
    await load.value

    XCTAssertEqual(store.readings, refreshed)
    XCTAssertNil(store.problem)
    withExtendedLifetime((warningSubscription, readingsSubscription)) {}
  }

  func testTerminalFailureClearsLiveStatus() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let store = HomeAssistantTemperatureStore(loader: loader)
    let load = Task {
      await store.load()
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    let livePublished = expectation(description: "Live status published")
    let liveSubscription = store.$isLive.dropFirst().sink { isLive in
      if isLive {
        livePublished.fulfill()
      }
    }

    loader.yieldRequest(
      0,
      update: .live([reading(id: "temperature")])
    )
    await fulfillment(of: [livePublished], timeout: 1)
    loader.failRequest(0, with: HomeAssistantAPIError.invalidResponse)
    await load.value

    XCTAssertFalse(store.isLive)
    XCTAssertEqual(store.problem, .invalidResponse)
    withExtendedLifetime(liveSubscription) {}
  }

  private func reading(id: String) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: id,
      name: id.localizedCapitalized,
      value: 22,
      targetValue: 23,
      unit: "°C",
      powerState: .poweredOn
    )
  }

  private func credentials() -> HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(string: "https://home.example")
        ?? URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

final class ControlledTemperatureLoader:
  HomeAssistantTemperatureLoading, @unchecked Sendable
{
  let providesContinuousTemperatureUpdates: Bool

  private let lock = NSLock()
  private let startedExpectations: [XCTestExpectation]
  private var continuations: [Int: HomeAssistantTemperatureUpdateStream.Continuation] = [:]
  private var cancellationExpectations: [Int: XCTestExpectation] = [:]
  private var cancelledRequestIDs: Set<Int> = []
  private var nextRequestID = 0

  var requestCount: Int { lock.withLock { nextRequestID } }

  init(requestCount: Int, providesContinuousUpdates: Bool = false) {
    providesContinuousTemperatureUpdates = providesContinuousUpdates
    startedExpectations = (0..<requestCount).map {
      XCTestExpectation(description: "Temperature request \($0) started")
    }
  }

  func started(at index: Int) -> XCTestExpectation {
    startedExpectations[index]
  }

  func temperatureUpdates() -> HomeAssistantTemperatureUpdateStream {
    HomeAssistantTemperatureUpdateStream { continuation in
      let request = lock.withLock { () -> (Int, XCTestExpectation?) in
        let requestID = nextRequestID
        nextRequestID += 1
        continuations[requestID] = continuation
        return (
          requestID,
          startedExpectations.indices.contains(requestID)
            ? startedExpectations[requestID] : nil
        )
      }
      let requestID = request.0
      guard let started = request.1 else {
        lock.withLock { continuations[requestID] = nil }
        continuation.finish(throwing: TemperatureLoaderError.unexpectedRequest)
        return
      }
      started.fulfill()
      continuation.onTermination = { termination in
        guard case .cancelled = termination else { return }
        let expectation = self.lock.withLock {
          self.cancelledRequestIDs.insert(requestID)
          self.continuations[requestID] = nil
          return self.cancellationExpectations[requestID]
        }
        expectation?.fulfill()
      }
    }
  }

  func succeedRequest(
    _ requestID: Int,
    with readings: [HomeAssistantTemperatureReading]
  ) {
    let continuation = lock.withLock {
      continuations.removeValue(forKey: requestID)
    }
    continuation?.yield(.live(readings))
    continuation?.finish()
  }

  func yieldRequest(_ requestID: Int, update: HomeAssistantTemperatureUpdate) {
    let continuation = lock.withLock {
      continuations[requestID]
    }
    continuation?.yield(update)
  }

  func finishRequest(_ requestID: Int) {
    let continuation = lock.withLock {
      continuations.removeValue(forKey: requestID)
    }
    continuation?.finish()
  }

  func failRequest(_ requestID: Int, with error: any Error) {
    let continuation = lock.withLock {
      continuations.removeValue(forKey: requestID)
    }
    continuation?.finish(throwing: error)
  }

  func cancelled(at index: Int) -> XCTestExpectation {
    lock.withLock {
      let expectation = XCTestExpectation(
        description: "Temperature request \(index) cancelled"
      )
      cancellationExpectations[index] = expectation
      if cancelledRequestIDs.contains(index) {
        expectation.fulfill()
      }
      return expectation
    }
  }
}

private final class CancellingTemperatureLoader:
  HomeAssistantTemperatureLoading, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Temperature request started")
  let cancelled = XCTestExpectation(description: "Temperature stream cancelled")

  func temperatureUpdates() -> HomeAssistantTemperatureUpdateStream {
    HomeAssistantTemperatureUpdateStream { continuation in
      started.fulfill()
      continuation.onTermination = { termination in
        if case .cancelled = termination {
          self.cancelled.fulfill()
        }
      }
    }
  }
}

@MainActor
private final class RestoredTemperatureConnection: HomeAssistantConnecting {
  private let credentials: HomeAssistantCredentials

  init(credentials: HomeAssistantCredentials) {
    self.credentials = credentials
  }

  func authenticate(
    to candidate: HomeAssistantConnectionCandidate
  ) async throws -> HomeAssistantCredentials {
    credentials
  }

  func restore() async throws -> HomeAssistantCredentials? {
    credentials
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    credentials
  }

  func disconnect() async throws {}
  func cancel() {}
}

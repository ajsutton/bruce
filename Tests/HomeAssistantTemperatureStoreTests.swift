import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantTemperatureStoreTests: XCTestCase {
  func testSuccessfulLoadPublishesReadingsAndCheckTime() async {
    let checkTime = Date(timeIntervalSince1970: 300)
    let readings = [
      reading(id: "first", updatedAt: Date(timeIntervalSince1970: 100)),
      reading(id: "second", updatedAt: Date(timeIntervalSince1970: 200)),
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
    let originalReadings = [reading(id: "temperature", updatedAt: .now)]
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
        results: [.success([reading(id: "temperature", updatedAt: .now)])]
      )
    )
    await store.load()

    await store.synchronize(with: .disconnected)

    XCTAssertTrue(store.readings.isEmpty)
    XCTAssertNil(store.lastChecked)
    XCTAssertNil(store.problem)
  }

  func testUnavailableConnectionRejectsLateSuccess() async {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let store = HomeAssistantTemperatureStore(loader: loader)
    let load = Task {
      await store.synchronize(with: .connected(credentials()))
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)

    await store.synchronize(with: .unavailable)
    loader.succeedRequest(0, with: [reading(id: "late", updatedAt: .now)])
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

    let newest = [reading(id: "newest", updatedAt: .now)]
    loader.succeedRequest(1, with: newest)
    await secondLoad.value
    loader.succeedRequest(0, with: [reading(id: "old", updatedAt: .now)])
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

    XCTAssertNil(store.problem)
    XCTAssertFalse(store.isLoading)
  }

  private func reading(
    id: String,
    updatedAt: Date?
  ) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: id,
      name: id.localizedCapitalized,
      value: 22,
      unit: "°C",
      updatedAt: updatedAt
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

private enum TemperatureLoaderError: Error, Sendable {
  case connectionUnavailable
  case signInRequired
}

private actor QueueTemperatureLoader: HomeAssistantTemperatureLoading {
  private var results: [Result<[HomeAssistantTemperatureReading], TemperatureLoaderError>]

  init(
    results: [Result<[HomeAssistantTemperatureReading], TemperatureLoaderError>]
  ) {
    self.results = results
  }

  func loadTemperatures() async throws -> [HomeAssistantTemperatureReading] {
    let result = results.removeFirst()
    switch result {
    case .success(let readings):
      return readings
    case .failure(.connectionUnavailable):
      throw URLError(.notConnectedToInternet)
    case .failure(.signInRequired):
      throw HomeAssistantAPIError.reauthenticationRequired
    }
  }
}

private final class ControlledTemperatureLoader:
  HomeAssistantTemperatureLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private let startedExpectations: [XCTestExpectation]
  private var continuations:
    [Int: CheckedContinuation<[HomeAssistantTemperatureReading], any Error>] = [:]
  private var nextRequestID = 0

  init(requestCount: Int) {
    startedExpectations = (0..<requestCount).map {
      XCTestExpectation(description: "Temperature request \($0) started")
    }
  }

  func started(at index: Int) -> XCTestExpectation {
    startedExpectations[index]
  }

  func loadTemperatures() async throws -> [HomeAssistantTemperatureReading] {
    try await withCheckedThrowingContinuation { continuation in
      let requestID = lock.withLock {
        let requestID = nextRequestID
        nextRequestID += 1
        continuations[requestID] = continuation
        return requestID
      }
      startedExpectations[requestID].fulfill()
    }
  }

  func succeedRequest(
    _ requestID: Int,
    with readings: [HomeAssistantTemperatureReading]
  ) {
    let continuation = lock.withLock {
      continuations.removeValue(forKey: requestID)
    }
    continuation?.resume(returning: readings)
  }
}

private final class CancellingTemperatureLoader:
  HomeAssistantTemperatureLoading, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Temperature request started")
  private let lock = NSLock()
  private var continuation: CheckedContinuation<[HomeAssistantTemperatureReading], any Error>?

  func loadTemperatures() async throws -> [HomeAssistantTemperatureReading] {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        lock.withLock {
          self.continuation = continuation
        }
        started.fulfill()
      }
    } onCancel: {
      let continuation = self.lock.withLock {
        let continuation = self.continuation
        self.continuation = nil
        return continuation
      }
      continuation?.resume(throwing: URLError(.cancelled))
    }
  }
}

@MainActor
private final class RestoredTemperatureConnection: HomeAssistantConnecting {
  private let credentials: HomeAssistantCredentials

  init(credentials: HomeAssistantCredentials) {
    self.credentials = credentials
  }

  func connect(
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

private struct EmptyTemperatureDiscovery: HomeAssistantDiscovering {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}

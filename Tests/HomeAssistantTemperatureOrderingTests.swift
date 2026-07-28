import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantTemperatureOrderingTests: XCTestCase {
  func testSameGenerationUpdatesReuseBlockedContextLoad() async throws {
    let setup = try await temperatureOrderingSetup()
    let (source, loader, probe) = (setup.source, setup.loader, setup.probe)
    await fulfillment(of: [source.started], timeout: 1)
    let generation = UUID()
    source.yield(
      .live(try decodedTemperatureStates(value: 21), generation: generation)
    )
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    source.yield(
      .live(try decodedTemperatureStates(value: 22), generation: generation)
    )
    loader.succeed(
      at: 0,
      with: Data(#"{"unit_system":{"temperature":"°C"}}"#.utf8),
      statusCode: 200
    )
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    guard case .live(let readings) = try probe.value(at: 0) else {
      XCTFail("Expected the newest same-generation live data.")
      return
    }
    XCTAssertEqual(readings.map(\.value), [22])
    XCTAssertEqual(loader.requestCount, 1)
    source.finish()
    await probe.cancel()
  }

  func testReconnectWhileContextIsBlockedPublishesStaleStatus() async throws {
    let setup = try await temperatureOrderingSetup()
    let (source, loader, probe) = (setup.source, setup.loader, setup.probe)
    await fulfillment(of: [source.started], timeout: 1)
    let generation = UUID()
    source.yield(
      .live(try decodedTemperatureStates(value: 21), generation: generation)
    )
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    source.yield(
      .reconnecting(
        try decodedTemperatureStates(value: 21),
        generation: generation
      )
    )
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    XCTAssertEqual(try probe.value(at: 0), .reconnecting([]))
    loader.succeed(
      at: 0,
      with: Data(#"{"unit_system":{"temperature":"°C"}}"#.utf8),
      statusCode: 200
    )
    source.finish()
    await probe.cancel()
  }

  func testBlockedContextNeverPublishesSupersededLiveState() async throws {
    let setup = try await temperatureOrderingSetup()
    let (source, loader, probe) = (setup.source, setup.loader, setup.probe)

    await fulfillment(of: [source.started], timeout: 1)
    let firstGeneration = UUID()
    let replacementGeneration = UUID()
    source.yield(
      .live(
        try decodedTemperatureStates(value: 21),
        generation: firstGeneration
      )
    )
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    source.yield(
      .live(
        try decodedTemperatureStates(value: 23),
        generation: replacementGeneration
      )
    )
    await fulfillment(of: [loader.started(at: 1)], timeout: 1)
    loader.succeed(
      at: 0,
      with: Data(#"{"unit_system":{"temperature":"°C"}}"#.utf8),
      statusCode: 200
    )
    loader.succeed(
      at: 1,
      with: Data(#"{"unit_system":{"temperature":"°F"}}"#.utf8),
      statusCode: 200
    )
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    source.finish()
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)

    guard case .live(let readings) = try probe.value(at: 0) else {
      XCTFail("Expected replacement live data with its matching context.")
      return
    }
    XCTAssertEqual(readings.map(\.value), [23])
    XCTAssertEqual(readings.map(\.unit), ["°F"])
    XCTAssertThrowsError(try probe.value(at: 1))
  }
}

private func temperatureOrderingSetup() async throws -> TemperatureOrderingSetup {
  let fixture = SessionFixture()
  let loader = ControlledTemperatureContextLoader()
  let now = fixture.now
  let session = HomeAssistantSession(
    credentialStore: fixture.store,
    authenticationClient: HomeAssistantAuthenticationClient(
      loader: fixture.authenticationLoader,
      now: { now }
    ),
    loader: loader,
    now: { now }
  )
  try await session.install(fixture.credentials())
  let source = TemperatureContextStateSource()
  let stream = HomeAssistantTemperatureStream(
    states: source,
    apiClient: HomeAssistantAPIClient(
      session: session,
      climateMetadataLoader: TemperatureSubscriptionMetadataLoader(metadata: [:])
    )
  )
  return TemperatureOrderingSetup(
    source: source,
    loader: loader,
    probe: AsyncThrowingStreamTestProbe(stream.temperatureUpdates())
  )
}

private struct TemperatureOrderingSetup {
  let source: TemperatureContextStateSource
  let loader: ControlledTemperatureContextLoader
  let probe: AsyncThrowingStreamTestProbe<HomeAssistantTemperatureUpdate>
}

private func decodedTemperatureStates(value: Double) throws -> [HomeAssistantState] {
  try JSONDecoder().decode([HomeAssistantState].self, from: temperatureStates(value: value))
}

private final class TemperatureContextStateSource:
  HomeAssistantStateLoading, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Temperature state source started")

  private let lock = NSLock()
  private var continuation: AsyncThrowingStream<HomeAssistantStateUpdate, any Error>.Continuation?

  func stateUpdates() async -> AsyncThrowingStream<
    HomeAssistantStateUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func yield(_ update: HomeAssistantStateUpdate) {
    let continuation = lock.withLock { self.continuation }
    continuation?.yield(update)
  }

  func finish() {
    let continuation = lock.withLock { self.continuation }
    continuation?.finish()
  }
}

private final class ControlledTemperatureContextLoader:
  HomeAssistantHTTPDataLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var continuations: [CheckedContinuation<(Data, HTTPURLResponse), any Error>?] = []
  private var requests: [URLRequest] = []
  private var expectations: [Int: XCTestExpectation] = [:]

  var requestCount: Int {
    lock.withLock { requests.count }
  }

  func started(at index: Int) -> XCTestExpectation {
    lock.withLock {
      if let expectation = expectations[index] {
        return expectation
      }
      let expectation = XCTestExpectation(
        description: "Temperature context request \(index) started"
      )
      expectations[index] = expectation
      if requests.indices.contains(index) {
        expectation.fulfill()
      }
      return expectation
    }
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    try await withCheckedThrowingContinuation { continuation in
      let expectation = lock.withLock {
        let index = requests.count
        requests.append(request)
        continuations.append(continuation)
        return expectations[index]
      }
      expectation?.fulfill()
    }
  }

  func succeed(at index: Int, with data: Data, statusCode: Int) {
    let state = lock.withLock {
      let continuation = continuations[index]
      continuations[index] = nil
      return (continuation, requests[index].url)
    }
    guard let continuation = state.0,
      let url = state.1,
      let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      return
    }
    continuation.resume(returning: (data, response))
  }
}

import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantTemperatureGenerationTests: XCTestCase {
  func testEachUpdateStreamWaitsForItsOwnSubscription() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let source = DeferredTemperatureStateSource()
    let stream = HomeAssistantTemperatureStream(
      states: source,
      apiClient: HomeAssistantAPIClient(session: session)
    )

    try await verifySubscription(0, stream: stream, source: source)
    try await verifySubscription(1, stream: stream, source: source)
  }

  func testNewGenerationDoesNotReusePreviousMetadata() async throws {
    let setup = try await generationMetadataSetup()
    let (source, loader, probe) = (setup.source, setup.loader, setup.probe)
    await fulfillment(of: [source.started], timeout: 1)
    source.yield(
      .live(try decodedTemperatureStates(value: 21), generation: UUID())
    )
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    guard case .live(let originalReadings) = try probe.value(at: 0) else {
      XCTFail("Expected the first generation to become live.")
      return
    }
    XCTAssertEqual(originalReadings.map(\.icon), ["mdi:bed"])

    let failedGeneration = UUID()
    source.yield(
      .live(try decodedTemperatureStates(value: 22), generation: failedGeneration)
    )
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    XCTAssertEqual(try probe.value(at: 1), .refreshing(originalReadings))
    XCTAssertEqual(try probe.value(at: 2), .unavailable(originalReadings))
    for value in 23...30 {
      source.yield(
        .live(try decodedTemperatureStates(value: Double(value)), generation: failedGeneration)
      )
    }
    await Task.yield()
    XCTAssertEqual(loader.loadCount, 2)
    source.yield(
      .live(try decodedTemperatureStates(value: 31), generation: UUID())
    )
    await fulfillment(of: [probe.received(at: 4)], timeout: 1)
    guard case .live(let recovered) = try probe.value(at: 4) else {
      return XCTFail("Expected the same subscription to recover on a fresh generation.")
    }
    XCTAssertEqual(recovered.map(\.value), [31])
    XCTAssertEqual(loader.loadCount, 3)
    source.finish()
    await probe.cancel()
  }

  func testReplacementGenerationReloadsChangedConfigurationAndMetadata() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [configuration("°C"), configuration("°F")]
    )
    try await session.install(fixture.credentials())
    let loader = GenerationClimateMetadataLoader(
      results: [
        .success([
          "climate.bedroom": HomeAssistantClimateMetadata(
            icon: "mdi:bed",
            kind: .other
          )
        ]),
        .success([
          "climate.bedroom": HomeAssistantClimateMetadata(
            icon: "mdi:thermometer",
            kind: .other
          )
        ]),
      ]
    )
    let source = TemperatureContextStateSource()
    let stream = HomeAssistantTemperatureStream(
      states: source,
      apiClient: HomeAssistantAPIClient(
        session: session,
        climateMetadataLoader: loader
      )
    )
    let probe = AsyncThrowingStreamTestProbe(stream.temperatureUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(.live(try decodedTemperatureStates(value: 21), generation: UUID()))
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    source.yield(.live(try decodedTemperatureStates(value: 72), generation: UUID()))
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    XCTAssertEqual(try probe.value(at: 0).readings.first?.icon, "mdi:bed")
    XCTAssertEqual(try probe.value(at: 0).readings.first?.unit, "°C")
    XCTAssertEqual(try probe.value(at: 2).readings.first?.icon, "mdi:thermometer")
    XCTAssertEqual(try probe.value(at: 2).readings.first?.unit, "°F")
    XCTAssertEqual(loader.loadCount, 2)
    source.finish()
    await probe.cancel()
  }

  func testStaleMetadataLoadRetriesWithinTheSameGeneration() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [configuration("°C"), configuration("°C")]
    )
    try await session.install(fixture.credentials())
    let metadata = HomeAssistantClimateMetadata(icon: "mdi:bed", kind: .other)
    let loader = GenerationClimateMetadataLoader(
      results: [
        .failure(HomeAssistantAPIError.staleOperation),
        .success(["climate.bedroom": metadata]),
      ]
    )
    let source = TemperatureContextStateSource()
    let stream = HomeAssistantTemperatureStream(
      states: source,
      apiClient: HomeAssistantAPIClient(
        session: session,
        climateMetadataLoader: loader
      ),
      contextRetryDelays: [.zero],
      sleep: { _ in }
    )
    let probe = AsyncThrowingStreamTestProbe(stream.temperatureUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(.live(try decodedTemperatureStates(value: 21), generation: UUID()))
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    XCTAssertEqual(try probe.value(at: 0).readings.first?.icon, "mdi:bed")
    XCTAssertEqual(loader.loadCount, 2)
    source.finish()
    await probe.cancel()
  }

  private func verifySubscription(
    _ index: Int,
    stream: HomeAssistantTemperatureStream,
    source: DeferredTemperatureStateSource
  ) async throws {
    let updates = stream.temperatureUpdates()
    let completion = TemperatureSubscriptionCompletion()
    let wait = Task {
      try await updates.waitUntilSubscribed()
      completion.complete()
    }
    await fulfillment(of: [source.started(at: index)], timeout: 1)
    XCTAssertFalse(completion.isComplete)
    source.allowSubscription(at: index)
    try await wait.value
    updates.cancel()
  }
}

private struct GenerationMetadataSetup {
  let source: TemperatureContextStateSource
  let loader: GenerationClimateMetadataLoader
  let probe: AsyncThrowingStreamTestProbe<HomeAssistantTemperatureUpdate>
}

private func generationMetadataSetup() async throws -> GenerationMetadataSetup {
  let fixture = SessionFixture()
  let session = fixture.makeSession(
    apiResponses: [configuration("°C"), configuration("°F"), configuration("°C")]
  )
  try await session.install(fixture.credentials())
  let metadata = HomeAssistantClimateMetadata(icon: "mdi:bed", kind: .other)
  let loader = GenerationClimateMetadataLoader(
    results: [
      .success(["climate.bedroom": metadata]),
      .failure(HomeAssistantAPIError.server(statusCode: 503)),
      .success(["climate.bedroom": metadata]),
    ]
  )
  let source = TemperatureContextStateSource()
  let stream = HomeAssistantTemperatureStream(
    states: source,
    apiClient: HomeAssistantAPIClient(
      session: session,
      climateMetadataLoader: loader
    ),
    contextRetryDelays: []
  )
  return GenerationMetadataSetup(
    source: source,
    loader: loader,
    probe: AsyncThrowingStreamTestProbe(stream.temperatureUpdates())
  )
}

private func configuration(_ unit: String) -> QueueHomeAssistantLoader.Result {
  .success(
    Data(#"{"unit_system":{"temperature":"\#(unit)"}}"#.utf8),
    statusCode: 200
  )
}

private final class DeferredTemperatureStateSource:
  HomeAssistantStateLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var starts: [XCTestExpectation] = []
  private var registrations: [CheckedContinuation<Void, Never>?] = []

  func started(at index: Int) -> XCTestExpectation {
    lock.withLock {
      prepareStart(at: index)
      return starts[index]
    }
  }

  func stateUpdates() async -> HomeAssistantBufferedUpdateStream<
    HomeAssistantStateUpdate
  > {
    let index = lock.withLock {
      let index = registrations.count
      registrations.append(nil)
      prepareStart(at: index)
      return index
    }
    await withCheckedContinuation { continuation in
      let started = lock.withLock {
        registrations[index] = continuation
        return starts[index]
      }
      started.fulfill()
    }
    return HomeAssistantBufferedUpdateStream { _ in }
  }

  func allowSubscription(at index: Int) {
    let continuation = lock.withLock {
      let continuation = registrations[index]
      registrations[index] = nil
      return continuation
    }
    continuation?.resume()
  }

  private func prepareStart(at index: Int) {
    while starts.count <= index {
      starts.append(
        XCTestExpectation(description: "State subscription \(starts.count) started")
      )
    }
  }
}

private final class TemperatureSubscriptionCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var completed = false

  var isComplete: Bool { lock.withLock { completed } }

  func complete() {
    lock.withLock { completed = true }
  }
}

private final class GenerationClimateMetadataLoader:
  HomeAssistantClimateMetadataLoading, @unchecked Sendable
{
  typealias Output = [String: HomeAssistantClimateMetadata]

  private let lock = NSLock()
  private var results: [Result<Output, any Error>]
  private var storedLoadCount = 0

  init(results: [Result<Output, any Error>]) {
    self.results = results
  }

  var loadCount: Int { lock.withLock { storedLoadCount } }

  func loadClimateMetadata() async throws -> Output {
    let result = try lock.withLock {
      storedLoadCount += 1
      guard !results.isEmpty else { throw UnexpectedClimateMetadataRequest() }
      return results.removeFirst()
    }
    return try result.get()
  }
}

private struct UnexpectedClimateMetadataRequest: Error {}

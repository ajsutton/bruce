import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantGarageDoorStreamTests: XCTestCase {
  func testRegistryFailurePublishesUnavailableWithoutEndingObservation() async throws {
    let source = ControlledStateSource()
    let loader = TransientGarageDoorRegistryLoader()
    let stream = HomeAssistantGarageDoorStream(
      states: source,
      registryLoader: loader
    )
    let probe = AsyncThrowingStreamTestProbe(stream.garageDoorUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    let failedGeneration = UUID()
    source.yield(.live(try garageDoorStates(), generation: failedGeneration))
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    XCTAssertEqual(try probe.value(at: 0), .unavailable([]))
    for _ in 0..<8 {
      source.yield(.live(try garageDoorStates(), generation: failedGeneration))
    }
    await Task.yield()
    XCTAssertEqual(loader.requestCount, 1)
    source.yield(.live(try garageDoorStates(), generation: UUID()))
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    guard case .live(let recovered) = try probe.value(at: 1) else {
      return XCTFail("Expected the same stream to recover.")
    }
    XCTAssertEqual(recovered.first?.name, "Recovered Garage")
    source.finish()
    await probe.cancel()
  }

  func testNewGenerationControlUsesCachedDoorsUntilRegistryRefresh() async throws {
    let source = ControlledStateSource()
    let registryLoader = QueueGarageDoorRegistryLoader(
      names: ["Old Garage", "New Garage"]
    )
    let stream = HomeAssistantGarageDoorStream(
      states: source,
      registryLoader: registryLoader
    )
    let probe = AsyncThrowingStreamTestProbe(stream.garageDoorUpdates())
    await fulfillment(of: [source.started], timeout: 1)
    let oldGeneration = UUID()
    let newGeneration = UUID()

    source.yield(
      .live(try garageDoorStates(), generation: oldGeneration)
    )
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    source.yield(
      .reconnecting(try garageDoorStates(), generation: newGeneration)
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    source.yield(
      .live(try garageDoorStates(), generation: newGeneration)
    )
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    guard case .live(let initial) = try probe.value(at: 0),
      case .reconnecting(let reconnecting) = try probe.value(at: 1),
      case .live(let refreshed) = try probe.value(at: 2)
    else {
      return XCTFail("Expected live, reconnecting, then refreshed live doors.")
    }
    XCTAssertEqual(initial.first?.name, "Old Garage")
    XCTAssertEqual(reconnecting.first?.name, "Old Garage")
    XCTAssertEqual(refreshed.first?.name, "New Garage")
    XCTAssertEqual(registryLoader.requestCount, 2)
  }

  func testSupersededRegistryLoadCannotPublishAsNewGeneration() async throws {
    let source = ControlledStateSource()
    let registryLoader = ControlledGarageDoorRegistryLoader()
    let stream = HomeAssistantGarageDoorStream(
      states: source,
      registryLoader: registryLoader
    )
    let probe = AsyncThrowingStreamTestProbe(stream.garageDoorUpdates())
    await fulfillment(of: [source.started], timeout: 1)
    let oldGeneration = UUID()
    let newGeneration = UUID()

    source.yield(.live(try garageDoorStates(), generation: oldGeneration))
    await fulfillment(of: [registryLoader.requested(1)], timeout: 1)
    source.yield(
      .reconnecting(try garageDoorStates(), generation: newGeneration)
    )
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    source.yield(.live(try garageDoorStates(), generation: newGeneration))
    await fulfillment(of: [registryLoader.requested(2)], timeout: 1)

    registryLoader.succeed(request: 1, name: "Stale Garage")
    registryLoader.succeed(request: 2, name: "Current Garage")
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    source.finish()
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)

    guard case .reconnecting(let reconnecting) = try probe.value(at: 0),
      case .live(let live) = try probe.value(at: 1)
    else {
      return XCTFail("Expected stale control state followed by one current live value.")
    }
    XCTAssertTrue(reconnecting.isEmpty)
    XCTAssertEqual(live.first?.name, "Current Garage")
    XCTAssertEqual(registryLoader.requestCount, 2)
    XCTAssertThrowsError(try probe.value(at: 2))
  }

  func testRecoverableRegistryFailureRetriesWithoutFinishingStream() async throws {
    let source = ControlledStateSource()
    let registryLoader = RecoveringGarageDoorRegistryLoader()
    let stream = HomeAssistantGarageDoorStream(
      states: source,
      registryLoader: registryLoader,
      retryDelays: [.seconds(1)],
      sleep: { _ in }
    )
    let probe = AsyncThrowingStreamTestProbe(stream.garageDoorUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(.live(try garageDoorStates()))
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    guard case .live(let doors) = try probe.value(at: 0) else {
      return XCTFail("Expected live doors after the registry retry succeeded.")
    }
    XCTAssertEqual(doors.first?.name, "Recovered Garage")
    XCTAssertEqual(registryLoader.requestCount, 2)
  }

  private func garageDoorStates() throws -> [HomeAssistantState] {
    try JSONDecoder().decode(
      [HomeAssistantState].self,
      from: Data(
        """
        [
          {
            "entity_id": "cover.side_entry",
            "state": "opening",
            "attributes": {
              "device_class": "garage",
              "friendly_name": "Side Entry",
              "supported_features": 15
            }
          }
        ]
        """.utf8
      )
    )
  }
}

private final class QueueGarageDoorRegistryLoader:
  HomeAssistantGarageDoorRegistryLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var names: [String]
  private var storedRequestCount = 0

  init(names: [String]) {
    self.names = names
  }

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func loadGarageDoorRegistry() async throws -> HomeAssistantGarageDoorRegistry {
    let name = try lock.withLock {
      storedRequestCount += 1
      guard !names.isEmpty else { throw UnexpectedGarageDoorRegistryRequest() }
      return names.removeFirst()
    }
    return HomeAssistantGarageDoorRegistry(
      deviceIDByEntityID: ["cover.side_entry": "garage"],
      deviceNameByID: ["garage": name]
    )
  }
}

private struct UnexpectedGarageDoorRegistryRequest: Error {}

private final class TransientGarageDoorRegistryLoader:
  HomeAssistantGarageDoorRegistryLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var didFail = false
  private var storedRequestCount = 0

  var requestCount: Int { lock.withLock { storedRequestCount } }

  func loadGarageDoorRegistry() async throws -> HomeAssistantGarageDoorRegistry {
    let shouldFail = lock.withLock {
      storedRequestCount += 1
      defer { didFail = true }
      return !didFail
    }
    if shouldFail { throw HomeAssistantAPIError.invalidResponse }
    return HomeAssistantGarageDoorRegistry(
      deviceIDByEntityID: ["cover.side_entry": "garage"],
      deviceNameByID: ["garage": "Recovered Garage"]
    )
  }
}

private final class ControlledGarageDoorRegistryLoader:
  HomeAssistantGarageDoorRegistryLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var continuations:
    [Int: CheckedContinuation<HomeAssistantGarageDoorRegistry, any Error>] = [:]
  private var expectations: [Int: XCTestExpectation] = [:]
  private var storedRequestCount = 0

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func requested(_ count: Int) -> XCTestExpectation {
    let expectation = XCTestExpectation(
      description: "Registry loader received request \(count)"
    )
    let alreadyReached = lock.withLock {
      if storedRequestCount >= count {
        return true
      }
      expectations[count] = expectation
      return false
    }
    if alreadyReached {
      expectation.fulfill()
    }
    return expectation
  }

  func loadGarageDoorRegistry() async throws -> HomeAssistantGarageDoorRegistry {
    try await withCheckedThrowingContinuation { continuation in
      let expectation = lock.withLock {
        storedRequestCount += 1
        let request = storedRequestCount
        continuations[request] = continuation
        return expectations.removeValue(forKey: request)
      }
      expectation?.fulfill()
    }
  }

  func succeed(request: Int, name: String) {
    let continuation = lock.withLock {
      continuations.removeValue(forKey: request)
    }
    continuation?.resume(
      returning: HomeAssistantGarageDoorRegistry(
        deviceIDByEntityID: ["cover.side_entry": "garage"],
        deviceNameByID: ["garage": name]
      ))
  }
}

private final class RecoveringGarageDoorRegistryLoader:
  HomeAssistantGarageDoorRegistryLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var storedRequestCount = 0

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func loadGarageDoorRegistry() async throws -> HomeAssistantGarageDoorRegistry {
    let request = lock.withLock {
      storedRequestCount += 1
      return storedRequestCount
    }
    if request == 1 {
      throw HomeAssistantAPIError.server(statusCode: 503)
    }
    return HomeAssistantGarageDoorRegistry(
      deviceIDByEntityID: ["cover.side_entry": "garage"],
      deviceNameByID: ["garage": "Recovered Garage"]
    )
  }
}

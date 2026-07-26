import Network
import XCTest
import dnssd

@testable import Bruce

final class NetworkHomeAssistantDiscoveryTests: XCTestCase {
  func testWaitingPolicyDenialFinishesWithPermissionError() async {
    let browser = TestBonjourBrowser()
    let discovery = NetworkHomeAssistantDiscovery(
      makeBrowser: { browser },
      makeResolver: { _ in TestBonjourResolver() }
    )
    let task = Task {
      for try await _ in discovery.advertisements() {}
    }
    await fulfillment(of: [browser.started], timeout: 1)

    browser.send(
      .waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied)))
    )

    switch await task.result {
    case .failure(let error):
      XCTAssertEqual(error as? HomeAssistantDiscoveryError, .permissionDenied)
    case .success:
      XCTFail("Expected permission denial.")
    }
  }

  func testCancellationCleansUpBrowserAndActiveResolver() async {
    let browser = TestBonjourBrowser()
    let resolver = TestBonjourResolver()
    let discovery = NetworkHomeAssistantDiscovery(
      makeBrowser: { browser },
      makeResolver: { _ in resolver }
    )
    let task = Task {
      for try await _ in discovery.advertisements() {}
    }
    await fulfillment(of: [browser.started], timeout: 1)
    browser.sendResults([result(id: "home")])
    await fulfillment(of: [resolver.started], timeout: 1)

    task.cancel()
    _ = await task.result

    await fulfillment(of: [browser.cancelled, resolver.cancelled], timeout: 1)
  }

  func testStaleResolverCannotPublishForReappearedService() async throws {
    let browser = TestBonjourBrowser()
    let firstResolver = TestBonjourResolver()
    let secondResolver = TestBonjourResolver()
    let resolverFactory = TestResolverFactory(resolvers: [firstResolver, secondResolver])
    let discovery = NetworkHomeAssistantDiscovery(
      makeBrowser: { browser },
      makeResolver: { endpoint in resolverFactory.makeResolver(for: endpoint) }
    )
    var iterator = discovery.advertisements().makeAsyncIterator()
    await fulfillment(of: [browser.started], timeout: 1)

    browser.sendResults([result(id: "home")])
    _ = try await iterator.next()
    await fulfillment(of: [firstResolver.started], timeout: 1)

    browser.sendResults([])
    _ = try await iterator.next()
    browser.sendResults([result(id: "home")])
    _ = try await iterator.next()
    await fulfillment(of: [secondResolver.started], timeout: 1)

    firstResolver.becomeReady(at: .hostPort(host: "192.168.1.10", port: 8123))
    secondResolver.becomeReady(at: .hostPort(host: "192.168.1.20", port: 8123))

    let nextSnapshot = try await iterator.next()
    let resolved = try XCTUnwrap(nextSnapshot)
    XCTAssertEqual(
      resolved.first?.resolvedInternalURL,
      URL(string: "http://192.168.1.20:8123")
    )
  }

  private func result(id: String) -> BonjourBrowseResult {
    BonjourBrowseResult(
      id: id,
      serviceName: "Home",
      endpoint: .hostPort(host: "homeassistant.local", port: 8123),
      txt: ["uuid": id]
    )
  }
}

private final class TestBonjourBrowser: BonjourBrowsing, @unchecked Sendable {
  var stateUpdateHandler: (@Sendable (BonjourBrowserState) -> Void)?
  var resultsUpdateHandler: (@Sendable ([BonjourBrowseResult]) -> Void)?
  let started = XCTestExpectation(description: "Browser started")
  let cancelled = XCTestExpectation(description: "Browser cancelled")

  private let lock = NSLock()
  private var queue: DispatchQueue?

  func start(queue: DispatchQueue) {
    lock.withLock {
      self.queue = queue
    }
    started.fulfill()
  }

  func cancel() {
    cancelled.fulfill()
  }

  func send(_ state: BonjourBrowserState) {
    let callback = lock.withLock { (queue, stateUpdateHandler) }
    callback.0?.async {
      callback.1?(state)
    }
  }

  func sendResults(_ results: [BonjourBrowseResult]) {
    let callback = lock.withLock { (queue, resultsUpdateHandler) }
    callback.0?.async {
      callback.1?(results)
    }
  }
}

private final class TestBonjourResolver: BonjourResolving, @unchecked Sendable {
  var stateUpdateHandler: (@Sendable (BonjourResolverState) -> Void)?
  var remoteEndpoint: NWEndpoint? {
    lock.withLock { endpoint }
  }
  let started = XCTestExpectation(description: "Resolver started")
  let cancelled = XCTestExpectation(description: "Resolver cancelled")

  private let lock = NSLock()
  private var queue: DispatchQueue?
  private var endpoint: NWEndpoint?

  func start(queue: DispatchQueue) {
    lock.withLock {
      self.queue = queue
    }
    started.fulfill()
  }

  func cancel() {
    cancelled.fulfill()
  }

  func becomeReady(at endpoint: NWEndpoint) {
    let callback = lock.withLock {
      self.endpoint = endpoint
      return (queue, stateUpdateHandler)
    }
    callback.0?.async {
      callback.1?(.ready)
    }
  }
}

private final class TestResolverFactory: @unchecked Sendable {
  private let lock = NSLock()
  private var resolvers: [TestBonjourResolver]

  init(resolvers: [TestBonjourResolver]) {
    self.resolvers = resolvers
  }

  func makeResolver(for _: NWEndpoint) -> any BonjourResolving {
    lock.withLock {
      resolvers.removeFirst()
    }
  }
}

import XCTest

@testable import Bruce

final class HomeAssistantDiscoveryClientTests: XCTestCase {
  func testSnapshotsAreDeduplicatedAndSorted() async throws {
    let browser = TestDiscoveryBrowser(
      snapshots: [
        [
          advertisement(
            id: "second",
            name: "Zulu",
            uuid: "z",
            internalURL: "http://zulu.local:8123"
          ),
          advertisement(
            id: "first",
            name: "Alpha",
            uuid: "a",
            externalURL: "https://alpha.example.com"
          ),
          advertisement(
            id: "first-copy",
            name: "Alpha",
            uuid: "a",
            internalURL: "http://alpha.local:8123"
          ),
        ]
      ]
    )

    let snapshots = try await collect(HomeAssistantDiscoveryClient(browser: browser).snapshots())

    XCTAssertEqual(snapshots.count, 1)
    XCTAssertEqual(snapshots[0].instances.map(\.id), ["a", "z"])
    XCTAssertEqual(
      snapshots[0].instances[0].internalURL,
      URL(string: "http://alpha.local:8123")
    )
    XCTAssertEqual(
      snapshots[0].instances[0].externalURL,
      URL(string: "https://alpha.example.com")
    )
  }

  func testUpdatesAndRemovalProduceNewSnapshots() async throws {
    let first = advertisement(id: "one", name: "Home", uuid: "home")
    let resolved = HomeAssistantDiscoveryAdvertisement(
      id: first.id,
      serviceName: first.serviceName,
      txt: first.txt,
      resolvedInternalURL: URL(string: "http://192.168.1.2:8123")
    )
    let browser = ControlledDiscoveryBrowser()
    var iterator = HomeAssistantDiscoveryClient(browser: browser).snapshots().makeAsyncIterator()
    await fulfillment(of: [browser.started], timeout: 1)

    browser.send([first])
    let firstValue = try await iterator.next()
    let firstSnapshot = try XCTUnwrap(firstValue)
    browser.send([resolved])
    let resolvedValue = try await iterator.next()
    let resolvedSnapshot = try XCTUnwrap(resolvedValue)
    browser.send([])
    let emptyValue = try await iterator.next()
    let emptySnapshot = try XCTUnwrap(emptyValue)
    browser.finish()

    XCTAssertNil(firstSnapshot.instances[0].internalURL)
    XCTAssertEqual(
      resolvedSnapshot.instances[0].internalURL,
      URL(string: "http://192.168.1.2:8123")
    )
    XCTAssertTrue(emptySnapshot.instances.isEmpty)
  }

  func testMalformedAdvertisementsAreIgnored() async throws {
    let browser = TestDiscoveryBrowser(
      snapshots: [
        [
          HomeAssistantDiscoveryAdvertisement(
            id: "bad",
            serviceName: "Bad",
            txt: ["external_url": "not a URL"],
            resolvedInternalURL: nil
          ),
          advertisement(id: "good", name: "Good", uuid: "good"),
        ]
      ]
    )

    let snapshots = try await collect(HomeAssistantDiscoveryClient(browser: browser).snapshots())

    XCTAssertEqual(snapshots[0].instances.map(\.id), ["good"])
    XCTAssertEqual(
      snapshots[0].issues,
      [
        HomeAssistantDiscoveryIssue(
          advertisementID: "bad",
          serviceName: "Bad",
          problem: .missingUUID
        )
      ]
    )
  }

  func testBrowserFailureIsPropagated() async {
    let browser = TestDiscoveryBrowser(
      snapshots: [],
      error: HomeAssistantDiscoveryError.permissionDenied
    )

    do {
      _ = try await collect(HomeAssistantDiscoveryClient(browser: browser).snapshots())
      XCTFail("Expected discovery to fail.")
    } catch {
      XCTAssertEqual(error as? HomeAssistantDiscoveryError, .permissionDenied)
    }
  }

  func testCancellingConsumerCancelsBrowserStream() async {
    let browser = SuspendedDiscoveryBrowser()
    let task = Task {
      for try await _ in HomeAssistantDiscoveryClient(browser: browser).snapshots() {}
    }
    await fulfillment(of: [browser.started], timeout: 1)

    task.cancel()
    _ = await task.result

    await fulfillment(of: [browser.cancelled], timeout: 1)
  }

  private func collect<T>(
    _ stream: AsyncThrowingStream<T, any Error>
  ) async throws -> [T] {
    var values: [T] = []
    for try await value in stream {
      values.append(value)
    }
    return values
  }

  private func advertisement(
    id: String,
    name: String,
    uuid: String,
    internalURL: String? = nil,
    externalURL: String? = nil
  ) -> HomeAssistantDiscoveryAdvertisement {
    var txt = ["uuid": uuid, "location_name": name]
    txt["internal_url"] = internalURL
    txt["external_url"] = externalURL
    return HomeAssistantDiscoveryAdvertisement(
      id: id,
      serviceName: name,
      txt: txt,
      resolvedInternalURL: nil
    )
  }
}

private struct TestDiscoveryBrowser: HomeAssistantDiscoveryBrowsing {
  let snapshots: [[HomeAssistantDiscoveryAdvertisement]]
  var error: (any Error & Sendable)?

  func advertisements()
    -> AsyncThrowingStream<[HomeAssistantDiscoveryAdvertisement], any Error>
  {
    AsyncThrowingStream { continuation in
      for snapshot in snapshots {
        continuation.yield(snapshot)
      }
      if let error {
        continuation.finish(throwing: error)
      } else {
        continuation.finish()
      }
    }
  }
}

private final class ControlledDiscoveryBrowser: HomeAssistantDiscoveryBrowsing, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Controlled browser started")

  private let lock = NSLock()
  private var continuation:
    AsyncThrowingStream<[HomeAssistantDiscoveryAdvertisement], any Error>.Continuation?

  func advertisements()
    -> AsyncThrowingStream<[HomeAssistantDiscoveryAdvertisement], any Error>
  {
    AsyncThrowingStream { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func send(_ advertisements: [HomeAssistantDiscoveryAdvertisement]) {
    lock.withLock {
      continuation
    }?.yield(advertisements)
  }

  func finish() {
    lock.withLock {
      continuation
    }?.finish()
  }
}

private final class SuspendedDiscoveryBrowser: HomeAssistantDiscoveryBrowsing, @unchecked Sendable {
  let started = XCTestExpectation(description: "Suspended browser started")
  let cancelled = XCTestExpectation(description: "Suspended browser cancelled")

  func advertisements()
    -> AsyncThrowingStream<[HomeAssistantDiscoveryAdvertisement], any Error>
  {
    AsyncThrowingStream { continuation in
      continuation.onTermination = { [cancelled] _ in
        cancelled.fulfill()
      }
      started.fulfill()
    }
  }
}

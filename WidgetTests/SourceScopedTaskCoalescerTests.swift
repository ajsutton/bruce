import XCTest

final class SourceScopedTaskCoalescerTests: XCTestCase {
  func testReplacementSourceDoesNotJoinBlockedOldSourceRefresh() async {
    let coalescer = SourceScopedTaskCoalescer<String>()
    let gate = AsyncGate()
    let oldSourceStarted = expectation(description: "Old source refresh started")
    let oldRequest = Task {
      await coalescer.value(for: "old-source") {
        oldSourceStarted.fulfill()
        await gate.wait()
        return "old-value"
      }
    }
    await fulfillment(of: [oldSourceStarted], timeout: 1)

    let replacementValue = await coalescer.value(for: "replacement-source") {
      "replacement-value"
    }

    XCTAssertEqual(replacementValue, "replacement-value")
    await gate.open()
    let oldValue = await oldRequest.value
    XCTAssertEqual(oldValue, "old-value")
  }
}

private actor AsyncGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var isOpen = false

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func open() {
    if let continuation {
      continuation.resume()
      self.continuation = nil
    } else {
      isOpen = true
    }
  }
}

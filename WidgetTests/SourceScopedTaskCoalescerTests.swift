import XCTest

final class SourceScopedTaskCoalescerTests: XCTestCase {
  func testReplacementSourceDoesNotJoinBlockedOldSourceRefresh() async {
    let coalescer = SourceScopedTaskCoalescer<String>()
    let gate = AsyncGate()
    let oldSourceStarted = expectation(description: "Old source refresh started")
    let oldSourceCancelled = expectation(description: "Old source refresh cancelled")
    let oldRequest = Task {
      await coalescer.value(for: "old-source") {
        await withTaskCancellationHandler {
          oldSourceStarted.fulfill()
          await gate.wait()
          return "old-value"
        } onCancel: {
          oldSourceCancelled.fulfill()
        }
      }
    }
    await fulfillment(of: [oldSourceStarted], timeout: 1)

    let replacementValue = await coalescer.value(for: "replacement-source") {
      "replacement-value"
    }

    XCTAssertEqual(replacementValue, "replacement-value")
    await fulfillment(of: [oldSourceCancelled], timeout: 1)
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

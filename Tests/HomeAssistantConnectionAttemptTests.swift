import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantConnectionAttemptTests: XCTestCase {
  func testUnallocatedResponseIsRejected() async throws {
    let attempt = makeAttempt()
    do {
      try await attempt.receive(response(id: 1, marker: "unsolicited"))
      XCTFail("Expected unsolicited protocol data to be rejected")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Expected invalidResponse, got \(error)")
    }

    let id = try await attempt.allocateCommandID()
    try await attempt.receive(response(id: id, marker: "expected"))
    let received = try await attempt.response(for: id)

    XCTAssertTrue(try decodedMarker(from: received) == "expected")
  }

  func testCancellingBufferedResponseDoesNotHideDuplicate() async throws {
    let attempt = makeAttempt()
    let id = try await attempt.allocateCommandID()
    try await attempt.receive(response(id: id, marker: "buffered"))
    let gate = ConnectionAttemptTestGate()
    let task = Task {
      await gate.wait()
      return try await attempt.response(for: id)
    }

    task.cancel()
    await gate.open()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation to win over a buffered response")
    } catch is CancellationError {
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }

    do {
      try await attempt.receive(response(id: id, marker: "duplicate"))
      XCTFail("Expected a duplicate of the buffered response to be rejected")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Expected invalidResponse, got \(error)")
    }
  }

  func testCancellingOutstandingResponseAllowsExactlyOneLateResponse() async throws {
    let attempt = makeAttempt()
    let id = try await attempt.allocateCommandID()
    let task = Task { try await attempt.response(for: id) }

    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }

    try await attempt.receive(response(id: id, marker: "late"))
    do {
      try await attempt.receive(response(id: id, marker: "duplicate"))
      XCTFail("Expected a second late response to be rejected")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Expected invalidResponse, got \(error)")
    }
  }

  func testExcessiveAbandonedResponsesFinishAttemptAndBoundTracking() async throws {
    let attempt = makeAttempt()

    for _ in 0...64 {
      let id = try await attempt.allocateCommandID()
      let task = Task { try await attempt.response(for: id) }
      task.cancel()
      do {
        _ = try await task.value
        XCTFail("Expected cancellation")
      } catch is CancellationError {
      } catch HomeAssistantAPIError.invalidResponse {
        // The cancellation that crosses the bound finishes the attempt before the waiter resumes.
      } catch {
        XCTFail("Expected cancellation or invalidResponse, got \(error)")
      }
    }

    do {
      _ = try await attempt.allocateCommandID()
      XCTFail("Expected excessive abandoned responses to replace the attempt")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Expected invalidResponse, got \(error)")
    }
  }

  func testFinishErrorIsReturnedToSubsequentResponseWaiter() async throws {
    let attempt = makeAttempt()
    let id = try await attempt.allocateCommandID()

    await attempt.finish(throwing: ConnectionAttemptTestError.transportClosed)

    do {
      _ = try await attempt.response(for: id)
      XCTFail("Expected the attempt's finish error")
    } catch ConnectionAttemptTestError.transportClosed {
    } catch {
      XCTFail("Expected transportClosed, got \(error)")
    }
  }

  func testDuplicateCompletedResponseIsRejected() async throws {
    let attempt = makeAttempt()
    let id = try await attempt.allocateCommandID()
    try await attempt.receive(response(id: id, marker: "first"))
    _ = try await attempt.response(for: id)

    do {
      try await attempt.receive(response(id: id, marker: "duplicate"))
      XCTFail("Expected a duplicate response to be rejected")
    } catch HomeAssistantAPIError.invalidResponse {
    } catch {
      XCTFail("Expected invalidResponse, got \(error)")
    }
  }

  func testPublishingEventsCannotBeginAfterFinish() async {
    let attempt = makeAttempt()
    await attempt.finish(throwing: ConnectionAttemptTestError.transportClosed)

    do {
      _ = try await attempt.beginPublishingEvents()
      XCTFail("Expected the attempt's finish error")
    } catch ConnectionAttemptTestError.transportClosed {
    } catch {
      XCTFail("Expected transportClosed, got \(error)")
    }
  }

  private func makeAttempt() -> HomeAssistantConnectionAttempt {
    HomeAssistantConnectionAttempt(
      id: UUID(), authenticationSessionEpoch: 1, routeCategory: "preferred", now: { 0 }
    )
  }

  private func response(id: Int, marker: String) -> Data {
    Data(#"{"id":\#(id),"type":"result","marker":"\#(marker)"}"#.utf8)
  }

  private func decodedMarker(from data: Data) throws -> String? {
    try JSONDecoder().decode(ConnectionAttemptTestResponse.self, from: data).marker
  }
}

private actor ConnectionAttemptTestGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var isOpen = false

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation = $0 }
  }

  func open() {
    isOpen = true
    continuation?.resume()
    continuation = nil
  }
}

private enum ConnectionAttemptTestError: Error {
  case transportClosed
}

private struct ConnectionAttemptTestResponse: Decodable {
  let marker: String?
}

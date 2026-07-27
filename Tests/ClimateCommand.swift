import XCTest

@testable import Bruce

enum ClimateCommand: Equatable, Sendable {
  case power(entityID: String, isOn: Bool)
  case mode(entityID: String, mode: HomeAssistantTemperatureReading.ClimateMode)
}

actor RecordingClimateController: HomeAssistantClimateControlling {
  private(set) var commands: [ClimateCommand] = []

  func setPower(entityID: String, isOn: Bool) {
    commands.append(.power(entityID: entityID, isOn: isOn))
  }

  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) {
    commands.append(.mode(entityID: entityID, mode: mode))
  }
}

final class BlockingClimateController:
  HomeAssistantClimateControlling, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Climate command started")

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var storedCommands: [ClimateCommand] = []

  var commands: [ClimateCommand] {
    get async {
      lock.withLock { storedCommands }
    }
  }

  func setPower(entityID: String, isOn: Bool) async {
    lock.withLock {
      storedCommands.append(.power(entityID: entityID, isOn: isOn))
    }
    await withCheckedContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) {}

  func succeed() {
    let continuation = lock.withLock {
      let continuation = continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume()
  }
}

struct FailingClimateController: HomeAssistantClimateControlling {
  func setPower(entityID: String, isOn: Bool) async throws {
    throw URLError(.cannotConnectToHost)
  }

  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) async throws {
    throw URLError(.cannotConnectToHost)
  }
}

struct AuthenticationFailingClimateController: HomeAssistantClimateControlling {
  func setPower(entityID: String, isOn: Bool) async throws {
    throw HomeAssistantAPIError.reauthenticationRequired
  }

  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) async throws {
    throw HomeAssistantAPIError.reauthenticationRequired
  }
}

struct URLCancelledClimateController: HomeAssistantClimateControlling {
  func setPower(entityID: String, isOn: Bool) async throws {
    throw URLError(.cancelled)
  }

  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) async throws {
    throw URLError(.cancelled)
  }
}

final class CancellableClimateController:
  HomeAssistantClimateControlling, @unchecked Sendable
{
  let started = XCTestExpectation(description: "Climate command started")

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, any Error>?
  private var isCancelled = false

  func setPower(entityID: String, isOn: Bool) async throws {
    try await waitForCancellation()
  }

  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) async throws {
    try await waitForCancellation()
  }

  private func waitForCancellation() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let shouldCancel = lock.withLock {
          if isCancelled {
            return true
          }
          self.continuation = continuation
          return false
        }
        started.fulfill()
        if shouldCancel {
          continuation.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      let continuation = self.lock.withLock {
        self.isCancelled = true
        let continuation = self.continuation
        self.continuation = nil
        return continuation
      }
      continuation?.resume(throwing: CancellationError())
    }
  }
}

final class OrderedClimateController:
  HomeAssistantClimateControlling, @unchecked Sendable
{
  private let lock = NSLock()
  private let startedExpectations: [XCTestExpectation]
  private var continuations: [Int: CheckedContinuation<Void, any Error>] = [:]
  private var nextCommand = 0

  init(commandCount: Int) {
    startedExpectations = (0..<commandCount).map {
      XCTestExpectation(description: "Climate command \($0) started")
    }
  }

  func started(at index: Int) -> XCTestExpectation {
    startedExpectations[index]
  }

  func setPower(entityID: String, isOn: Bool) async throws {
    try await wait()
  }

  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) async throws {
    try await wait()
  }

  func fail(command: Int) {
    let continuation = lock.withLock {
      continuations.removeValue(forKey: command)
    }
    continuation?.resume(throwing: URLError(.cannotConnectToHost))
  }

  func succeed(command: Int) {
    let continuation = lock.withLock {
      continuations.removeValue(forKey: command)
    }
    continuation?.resume()
  }

  private func wait() async throws {
    try await withCheckedThrowingContinuation { continuation in
      let command = lock.withLock {
        let command = nextCommand
        nextCommand += 1
        continuations[command] = continuation
        return command
      }
      startedExpectations[command].fulfill()
    }
  }
}

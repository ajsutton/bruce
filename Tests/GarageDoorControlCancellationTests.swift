import XCTest

@testable import Bruce

@MainActor
final class GarageDoorControlCancellationTests: XCTestCase {
  func testCancellingAccessoryControlsRestoresAuthoritativeStateWithoutError() async {
    let lightController = CancellationAwareGarageController(operation: .light)
    let original = door()
    let lightStore = store(controller: lightController, door: original)
    let light = Task { await lightStore.toggleLight(for: original) }
    await fulfillment(of: [lightController.started], timeout: 1)
    light.cancel()
    await light.value

    XCTAssertEqual(lightStore.doors.first?.lightState, .off)
    XCTAssertFalse(lightStore.isControlling(.light, for: original.id))
    XCTAssertNil(lightStore.problem)

    let lockController = CancellationAwareGarageController(operation: .lock)
    let lockStore = store(controller: lockController, door: original)
    let lock = Task { await lockStore.toggleLock(for: original) }
    await fulfillment(of: [lockController.started], timeout: 1)
    lock.cancel()
    await lock.value

    XCTAssertEqual(lockStore.doors.first?.lockState, .unlocked)
    XCTAssertFalse(lockStore.isControlling(.lock, for: original.id))
    XCTAssertNil(lockStore.problem)
  }

  func testCancellingDoorCommandClearsPendingStateWithoutError() async {
    let controller = CancellationAwareGarageController(operation: .door)
    let movingDoor = door(state: .opening)
    let store = store(controller: controller, door: movingDoor)
    let command = Task { await store.send(.stop, to: movingDoor) }
    await fulfillment(of: [controller.started], timeout: 1)

    command.cancel()
    await command.value

    XCTAssertNil(store.pendingDoorCommands[movingDoor.id])
    XCTAssertNil(store.problem)
  }

  private func store(
    controller: CancellationAwareGarageController,
    door: HomeAssistantGarageDoorSnapshot
  ) -> HomeAssistantGarageDoorStore {
    HomeAssistantGarageDoorStore(
      loader: TestGarageDoorLoader(),
      controller: controller,
      doors: [door],
      isLive: true
    )
  }

  private func door(
    state: HomeAssistantGarageDoorSnapshot.DoorState = .closed
  ) -> HomeAssistantGarageDoorSnapshot {
    HomeAssistantGarageDoorSnapshot(
      id: "cover.garage",
      name: "Garage Door",
      doorState: state,
      lightState: .off,
      lockState: .unlocked,
      lightEntityID: "light.garage",
      lockEntityID: "lock.garage",
      supportsStop: true
    )
  }
}

private final class CancellationAwareGarageController:
  HomeAssistantGarageDoorControlling, @unchecked Sendable
{
  enum Operation {
    case light
    case lock
    case door
  }

  let started = XCTestExpectation(description: "Garage control request started")

  private let operation: Operation
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, any Error>?
  private var cancellationRequested = false

  init(operation: Operation) {
    self.operation = operation
  }

  func setGarageLight(entityID _: String, isOn _: Bool) async throws {
    guard operation == .light else { throw CancellationTestError.unexpectedRequest }
    try await waitForCancellation()
  }

  func setGarageLock(entityID _: String, isLocked _: Bool) async throws {
    guard operation == .lock else { throw CancellationTestError.unexpectedRequest }
    try await waitForCancellation()
  }

  func sendGarageDoorCommand(
    _ command: HomeAssistantGarageDoorCommand,
    entityID _: String
  ) async throws {
    guard operation == .door, command == .stop else {
      throw CancellationTestError.unexpectedRequest
    }
    try await waitForCancellation()
  }

  private func waitForCancellation() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let wasCancelled = lock.withLock {
          if cancellationRequested { return true }
          self.continuation = continuation
          return false
        }
        if wasCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          started.fulfill()
        }
      }
    } onCancel: {
      let continuation = self.lock.withLock {
        self.cancellationRequested = true
        let continuation = self.continuation
        self.continuation = nil
        return continuation
      }
      continuation?.resume(throwing: CancellationError())
    }
  }
}

private enum CancellationTestError: Error {
  case unexpectedRequest
}

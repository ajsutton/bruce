import Combine
import XCTest

@testable import Bruce

@MainActor
final class GarageDoorControlConcurrencyTests: XCTestCase {
  func testDoorTimeoutStartsBeforeServiceRequestReturns() async {
    let controller = BlockingGarageDoorController()
    let timeout = ControlledGarageDoorDelay()
    let movingDoor = door(state: .opening)
    let store = HomeAssistantGarageDoorStore(
      loader: TestGarageDoorLoader(),
      controller: controller,
      doors: [movingDoor],
      isLive: true,
      timeoutSleep: timeout.sleep
    )
    let stopStarted = await controller.expectDoorCommand(.stop)
    let command = Task { await store.send(.stop, to: movingDoor) }
    await fulfillment(of: [stopStarted, timeout.started], timeout: 1)

    timeout.resume()
    await waitForValue(store.$problem, matching: .updateFailed)

    XCTAssertNil(store.pendingDoorCommands[movingDoor.id])
    await controller.succeedDoorCommand(.stop)
    await command.value
  }

  func testAccessoryTimeoutRestoresLastAuthoritativeState() async {
    let controller = BlockingGarageDoorController()
    let timeout = ControlledGarageDoorDelay()
    let original = door(state: .closed)
    let store = HomeAssistantGarageDoorStore(
      loader: TestGarageDoorLoader(),
      controller: controller,
      doors: [original],
      isLive: true,
      timeoutSleep: timeout.sleep
    )
    let lightStarted = await controller.expectLight()
    let light = Task { await store.toggleLight(for: original) }
    await fulfillment(of: [lightStarted, timeout.started], timeout: 1)

    timeout.resume()
    await waitForValue(store.$problem, matching: .updateFailed)

    XCTAssertEqual(store.doors.first?.lightState, .off)
    XCTAssertFalse(store.isControlling(.light, for: original.id))
    await controller.succeedLight()
    await light.value
  }

  func testLateOpenCompletionCannotReplaceInterruptingStop() async {
    let setup = await connectedSetup(door: door(state: .closed))
    let openStarted = await setup.controller.expectDoorCommand(.open)
    let open = Task { await setup.store.send(.open, to: setup.store.doors[0]) }
    await fulfillment(of: [openStarted], timeout: 1)

    setup.loader.yield(.live([door(state: .opening)]))
    await waitForValue(
      setup.store.$pendingDoorCommands.map { $0["cover.garage"] },
      matching: nil
    )
    let stopStarted = await setup.controller.expectDoorCommand(.stop)
    let stop = Task { await setup.store.send(.stop, to: setup.store.doors[0]) }
    await fulfillment(of: [stopStarted], timeout: 1)

    await setup.controller.succeedDoorCommand(.open)
    await open.value
    XCTAssertEqual(setup.store.pendingDoorCommands["cover.garage"], .stop)

    setup.loader.yield(.live([door(state: .partlyOpen)]))
    await waitForValue(
      setup.store.$pendingDoorCommands.map { $0["cover.garage"] },
      matching: nil
    )
    await setup.controller.succeedDoorCommand(.stop)
    await stop.value
    setup.observation.cancel()
    await setup.observation.value
  }

  func testRequestedAccessoryStateSurvivesNonConfirmingLiveUpdate() async {
    let setup = await connectedSetup(door: door(state: .closed))
    let lightStarted = await setup.controller.expectLight()
    let light = Task { await setup.store.toggleLight(for: setup.store.doors[0]) }
    await fulfillment(of: [lightStarted], timeout: 1)
    setup.loader.yield(.live([door(state: .closed)]))
    await waitForValue(
      setup.store.$doors.map(\.first?.lightState),
      matching: .illuminated
    )
    XCTAssertTrue(setup.store.isControlling(.light, for: "cover.garage"))

    setup.loader.yield(.live([door(state: .closed, light: .illuminated)]))
    await waitForControl(.light, active: false, in: setup.store)
    await setup.controller.succeedLight()
    await light.value

    let lockStarted = await setup.controller.expectLock()
    let lock = Task { await setup.store.toggleLock(for: setup.store.doors[0]) }
    await fulfillment(of: [lockStarted], timeout: 1)
    setup.loader.yield(.live([door(state: .closed, light: .illuminated)]))
    await waitForValue(setup.store.$doors.map(\.first?.lockState), matching: .locking)
    setup.loader.yield(
      .live([door(state: .closed, light: .illuminated, lock: .locked)])
    )
    await waitForControl(.lock, active: false, in: setup.store)
    await setup.controller.succeedLock()
    await lock.value
    setup.observation.cancel()
    await setup.observation.value
  }

  func testFailureAndConnectionLossRestoreAuthoritativeAccessoryState() async {
    let setup = await connectedSetup(door: door(state: .closed))
    let lightStarted = await setup.controller.expectLight()
    let light = Task { await setup.store.toggleLight(for: setup.store.doors[0]) }
    await fulfillment(of: [lightStarted], timeout: 1)
    setup.loader.yield(.live([door(state: .closed)]))
    await setup.controller.failLight()
    await light.value
    XCTAssertEqual(setup.store.doors.first?.lightState, .off)

    let lockStarted = await setup.controller.expectLock()
    let lock = Task { await setup.store.toggleLock(for: setup.store.doors[0]) }
    await fulfillment(of: [lockStarted], timeout: 1)
    await setup.store.synchronize(with: .unavailable)
    XCTAssertEqual(setup.store.doors.first?.lockState, .unlocked)
    XCTAssertFalse(setup.store.isControlling(.lock, for: "cover.garage"))
    await setup.controller.succeedLock()
    await lock.value
    setup.observation.cancel()
    await setup.observation.value
  }

  private func connectedSetup(
    door: HomeAssistantGarageDoorSnapshot
  ) async -> GarageControlSetup {
    let loader = StreamingGarageDoorLoader()
    let controller = BlockingGarageDoorController()
    let store = HomeAssistantGarageDoorStore(loader: loader, controller: controller)
    let observation = Task { await store.synchronize(with: .connected(credentials)) }
    await fulfillment(of: [loader.started], timeout: 1)
    loader.yield(.live([door]))
    await waitForValue(store.$isLive, matching: true)
    return GarageControlSetup(
      loader: loader,
      controller: controller,
      store: store,
      observation: observation
    )
  }

  private func waitForControl(
    _ control: HomeAssistantGarageDoorStore.Control,
    active: Bool,
    in store: HomeAssistantGarageDoorStore
  ) async {
    await waitForValue(
      store.$controlsInFlight.map { $0["cover.garage"]?.contains(control) == true },
      matching: active
    )
  }

  private func waitForValue<P: Publisher>(
    _ publisher: P,
    matching expectedValue: P.Output
  ) async where P.Output: Equatable, P.Failure == Never {
    let published = expectation(description: "Expected published value")
    let subscription = publisher.filter { $0 == expectedValue }.prefix(1).sink { _ in
      published.fulfill()
    }
    await fulfillment(of: [published], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  private func door(
    state: HomeAssistantGarageDoorSnapshot.DoorState,
    light: HomeAssistantGarageDoorSnapshot.LightState = .off,
    lock: HomeAssistantGarageDoorSnapshot.LockState = .unlocked
  ) -> HomeAssistantGarageDoorSnapshot {
    HomeAssistantGarageDoorSnapshot(
      id: "cover.garage",
      name: "Garage Door",
      doorState: state,
      lightState: light,
      lockState: lock,
      lightEntityID: "light.garage",
      lockEntityID: "lock.garage",
      supportsStop: true
    )
  }

  private var credentials: HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(string: "https://home.example")!,
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

private struct GarageControlSetup {
  let loader: StreamingGarageDoorLoader
  let controller: BlockingGarageDoorController
  let store: HomeAssistantGarageDoorStore
  let observation: Task<Void, Never>
}

private actor BlockingGarageDoorController: HomeAssistantGarageDoorControlling {
  private var lightContinuation: CheckedContinuation<Void, any Error>?
  private var lockContinuation: CheckedContinuation<Void, any Error>?
  private var doorContinuations:
    [HomeAssistantGarageDoorCommand: CheckedContinuation<Void, any Error>] = [:]
  private var lightExpectation: XCTestExpectation?
  private var lockExpectation: XCTestExpectation?
  private var doorExpectations: [HomeAssistantGarageDoorCommand: XCTestExpectation] = [:]

  func setGarageLight(entityID _: String, isOn _: Bool) async throws {
    try await withCheckedThrowingContinuation {
      lightContinuation = $0
      lightExpectation?.fulfill()
      lightExpectation = nil
    }
  }

  func setGarageLock(entityID _: String, isLocked _: Bool) async throws {
    try await withCheckedThrowingContinuation {
      lockContinuation = $0
      lockExpectation?.fulfill()
      lockExpectation = nil
    }
  }

  func sendGarageDoorCommand(
    _ command: HomeAssistantGarageDoorCommand,
    entityID _: String
  ) async throws {
    try await withCheckedThrowingContinuation {
      doorContinuations[command] = $0
      doorExpectations.removeValue(forKey: command)?.fulfill()
    }
  }

  func expectLight() -> XCTestExpectation {
    let expectation = XCTestExpectation(description: "Garage light request started")
    lightExpectation = expectation
    return expectation
  }

  func expectLock() -> XCTestExpectation {
    let expectation = XCTestExpectation(description: "Garage lock request started")
    lockExpectation = expectation
    return expectation
  }

  func expectDoorCommand(
    _ command: HomeAssistantGarageDoorCommand
  ) -> XCTestExpectation {
    let expectation = XCTestExpectation(description: "\(command) request started")
    doorExpectations[command] = expectation
    return expectation
  }

  func failLight() {
    lightContinuation?.resume(throwing: GarageControlError.failed)
    lightContinuation = nil
  }

  func succeedLight() {
    lightContinuation?.resume()
    lightContinuation = nil
  }

  func succeedLock() {
    lockContinuation?.resume()
    lockContinuation = nil
  }

  func succeedDoorCommand(_ command: HomeAssistantGarageDoorCommand) {
    doorContinuations.removeValue(forKey: command)?.resume()
  }
}

private enum GarageControlError: Error {
  case failed
}

private final class ControlledGarageDoorDelay: @unchecked Sendable {
  let started = XCTestExpectation(description: "Garage command timeout started")
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  func sleep(for _: Duration) async {
    started.fulfill()
    await withCheckedContinuation { continuation in
      lock.withLock { self.continuation = continuation }
    }
  }

  func resume() {
    lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      continuation?.resume()
    }
  }
}

import Combine
import XCTest

@testable import Bruce

@MainActor
final class HomeAssistantGarageDoorStoreTests: XCTestCase {
  func testLightAndLockControlsUpdateTheirCompanionEntities() async {
    let loader = StreamingGarageDoorLoader()
    let controller = RecordingGarageDoorController()
    let original = door(state: .closed)
    let store = HomeAssistantGarageDoorStore(
      loader: loader,
      controller: controller,
      doors: [original]
    )
    let observation = Task {
      await store.synchronize(with: .ready(credentials))
    }
    await fulfillment(of: [loader.started], timeout: 1)
    loader.yield(.live([original]))
    await waitForValue(store.$isLive, matching: true)

    await store.toggleLight(for: original)
    XCTAssertTrue(store.isControlling(.light, for: original.id))
    loader.yield(.live([door(state: .closed, light: .illuminated)]))
    await waitForValue(
      store.$controlsInFlight.map { $0[original.id]?.contains(.light) == true },
      matching: false
    )
    let lightUpdated = store.doors.first
    await store.toggleLock(for: lightUpdated ?? original)
    XCTAssertTrue(store.isControlling(.lock, for: original.id))
    loader.yield(.live([door(state: .closed, light: .illuminated, lock: .locked)]))
    await waitForValue(
      store.$controlsInFlight.map { $0[original.id]?.contains(.lock) == true },
      matching: false
    )
    let recordedEvents = await controller.recordedEvents()

    XCTAssertEqual(store.doors.first?.lightState, .illuminated)
    XCTAssertEqual(store.doors.first?.lockState, .locked)
    XCTAssertEqual(
      recordedEvents,
      [
        .light(entityID: "light.garage", isOn: true),
        .lock(entityID: "lock.garage", isLocked: true),
      ]
    )
    observation.cancel()
    await observation.value
  }

  func testStopCommandRemainsPendingUntilDoorStopsMoving() async throws {
    let loader = StreamingGarageDoorLoader()
    let controller = RecordingGarageDoorController()
    let store = HomeAssistantGarageDoorStore(
      loader: loader,
      controller: controller
    )
    let observation = Task {
      await store.synchronize(with: .ready(credentials))
    }
    await fulfillment(of: [loader.started], timeout: 1)
    loader.yield(.live([door(state: .opening)]))
    await waitForDoorState(.opening, in: store)

    let movingDoor = try XCTUnwrap(store.doors.first)
    await store.send(.stop, to: movingDoor)

    XCTAssertEqual(store.pendingDoorCommands["cover.garage"], .stop)
    loader.yield(.live([door(state: .partlyOpen)]))
    await waitForDoorState(.partlyOpen, in: store)
    let recordedEvents = await controller.recordedEvents()
    XCTAssertNil(store.pendingDoorCommands["cover.garage"])
    XCTAssertEqual(
      recordedEvents,
      [.door(entityID: "cover.garage", command: .stop)]
    )
    observation.cancel()
    await observation.value
  }

  func testLiveDoorMovementUpdatesRemainVisibleUntilClosed() async {
    let loader = StreamingGarageDoorLoader()
    let store = HomeAssistantGarageDoorStore(loader: loader)
    let observation = Task {
      await store.synchronize(
        with: .ready(credentials)
      )
    }
    await fulfillment(of: [loader.started], timeout: 1)

    loader.yield(.live([door(state: .opening)]))
    await waitForDoorState(.opening, in: store)
    loader.yield(.live([door(state: .closing)]))
    await waitForDoorState(.closing, in: store)
    loader.yield(.live([door(state: .closed)]))
    await waitForDoorState(.closed, in: store)

    XCTAssertTrue(store.isLive)
    observation.cancel()
    await observation.value
  }

  func testUnavailableStateDoesNotConfirmStop() async {
    let loader = StreamingGarageDoorLoader()
    let store = HomeAssistantGarageDoorStore(
      loader: loader,
      controller: RecordingGarageDoorController()
    )
    let observation = Task {
      await store.synchronize(with: .ready(credentials))
    }
    await fulfillment(of: [loader.started], timeout: 1)
    loader.yield(.live([door(state: .opening)]))
    await waitForDoorState(.opening, in: store)

    await store.send(.stop, to: store.doors[0])
    loader.yield(.live([door(state: .unavailable)]))
    await waitForDoorState(.unavailable, in: store)

    XCTAssertEqual(store.pendingDoorCommands["cover.garage"], .stop)
    observation.cancel()
    await observation.value
  }

  func testSuccessfulEmptyDiscoveryIsDistinctFromFailure() async {
    let emptyStore = HomeAssistantGarageDoorStore(loader: TestGarageDoorLoader())
    let emptyObservation = Task {
      await emptyStore.synchronize(with: .ready(credentials))
    }
    await waitForValue(emptyStore.$hasCompletedDiscovery, matching: true)
    XCTAssertTrue(emptyStore.doors.isEmpty)
    XCTAssertNil(emptyStore.problem)
    emptyObservation.cancel()
    await emptyObservation.value

    let failingStore = HomeAssistantGarageDoorStore(loader: FailingGarageDoorLoader())
    await failingStore.synchronize(with: .ready(credentials))
    XCTAssertFalse(failingStore.hasCompletedDiscovery)
    XCTAssertEqual(failingStore.problem, .invalidResponse)
  }

  private func waitForDoorState(
    _ state: HomeAssistantGarageDoorSnapshot.DoorState,
    in store: HomeAssistantGarageDoorStore
  ) async {
    let published = expectation(description: "Expected garage door state \(state)")
    let subscription = store.$doors
      .filter { $0.first?.doorState == state }
      .prefix(1)
      .sink { _ in published.fulfill() }
    await fulfillment(of: [published], timeout: 1)
    withExtendedLifetime(subscription) {}
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
      lastSuccessfulURL: URL(string: "https://home.example")
        ?? URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

private actor RecordingGarageDoorController:
  HomeAssistantGarageDoorControlling
{
  enum Event: Equatable, Sendable {
    case light(entityID: String, isOn: Bool)
    case lock(entityID: String, isLocked: Bool)
    case door(entityID: String, command: HomeAssistantGarageDoorCommand)
  }

  private var events: [Event] = []

  func setGarageLight(entityID: String, isOn: Bool) {
    events.append(.light(entityID: entityID, isOn: isOn))
  }

  func setGarageLock(entityID: String, isLocked: Bool) {
    events.append(.lock(entityID: entityID, isLocked: isLocked))
  }

  func sendGarageDoorCommand(
    _ command: HomeAssistantGarageDoorCommand,
    entityID: String
  ) {
    events.append(.door(entityID: entityID, command: command))
  }

  func recordedEvents() -> [Event] {
    events
  }
}

private struct FailingGarageDoorLoader: HomeAssistantGarageDoorLoading {
  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] {
    throw HomeAssistantAPIError.invalidResponse
  }
}

final class StreamingGarageDoorLoader:
  HomeAssistantGarageDoorLoading, @unchecked Sendable
{
  let providesContinuousUpdates = true
  let started = XCTestExpectation(description: "Garage door updates started")

  private let lock = NSLock()
  private var continuation: HomeAssistantGarageDoorUpdateStream.Continuation?

  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] {
    []
  }

  func garageDoorUpdates() -> HomeAssistantGarageDoorUpdateStream {
    HomeAssistantGarageDoorUpdateStream { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      started.fulfill()
    }
  }

  func yield(
    _ update: HomeAssistantLiveUpdate<[HomeAssistantGarageDoorSnapshot]>
  ) {
    lock.withLock { continuation }?.yield(update)
  }
}

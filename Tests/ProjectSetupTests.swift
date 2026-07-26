import XCTest

@testable import Bruce

@MainActor
final class ProjectSetupTests: XCTestCase {
  func testContentViewCanBeCreated() {
    _ = ContentView(modeController: BruceModeController())
  }

  func testBruceDefaultsToStandardWhenNoPreferenceExists() async {
    let store = TestModeStore()
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    await controller.synchronize()

    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(iconApplier.appliedModes, [.standard])
  }

  func testUserDefaultsStoreDefaultsToStandardForAbsentOrInvalidValues() {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated user defaults.")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsBruceModeStore(defaults: defaults)

    XCTAssertEqual(store.loadMode(), .standard)

    defaults.set("not-a-bruce-mode", forKey: BruceMode.storageKey)
    XCTAssertEqual(store.loadMode(), .standard)
  }

  func testUserDefaultsStoreSavesAndRestoresAValidMode() {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated user defaults.")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsBruceModeStore(defaults: defaults)

    store.saveMode(.full)

    XCTAssertEqual(UserDefaultsBruceModeStore(defaults: defaults).loadMode(), .full)
  }

  func testPersistedFullBruceIsRestoredAfterItsIconIsApplied() async {
    let store = TestModeStore(mode: .full)
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    XCTAssertEqual(controller.mode, .standard)
    await controller.synchronize()

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(iconApplier.appliedModes, [.full])
  }

  func testCancelledSynchronizationPreservesPreferenceAndCanRetry() async {
    let store = TestModeStore(mode: .full)
    let iconApplier = CancellingOnceIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    await controller.synchronize()

    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(store.mode, .full)
    XCTAssertNil(controller.appIconErrorMessage)

    await controller.synchronize()

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(iconApplier.attemptCount, 2)
  }

  func testSelectingFullBruceAppliesItsIconBeforePersistingTheMode() async {
    let eventRecorder = TestEventRecorder()
    let store = TestModeStore(eventRecorder: eventRecorder)
    let iconApplier = TestIconApplier(eventRecorder: eventRecorder)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.synchronize()

    await controller.select(.full)

    XCTAssertEqual(
      eventRecorder.events,
      [.applyIcon(.standard), .applyIcon(.full), .saveMode(.full)]
    )
    XCTAssertEqual(store.mode, .full)
    XCTAssertEqual(controller.mode, .full)
  }

  func testIconFailureKeepsTheCurrentCoordinatedMode() async {
    let store = TestModeStore()
    let iconApplier = TestIconApplier(failingMode: .full, error: .unavailable)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.synchronize()

    await controller.select(.full)

    XCTAssertEqual(store.mode, .standard)
    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(
      controller.appIconErrorMessage,
      "The current look is still active."
    )
  }

  func testUnsupportedFullBruceIconKeepsStandardMode() async {
    let store = TestModeStore()
    let iconApplier = TestIconApplier(failingMode: .full, error: .unsupported)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.synchronize()

    await controller.select(.full)

    XCTAssertFalse(controller.mode.isFullBruce)
  }
}

private final class TestModeStore: BruceModeStoring {
  var mode: BruceMode
  private let eventRecorder: TestEventRecorder?

  init(mode: BruceMode = .standard, eventRecorder: TestEventRecorder? = nil) {
    self.mode = mode
    self.eventRecorder = eventRecorder
  }

  func loadMode() -> BruceMode {
    mode
  }

  func saveMode(_ mode: BruceMode) {
    eventRecorder?.events.append(.saveMode(mode))
    self.mode = mode
  }
}

@MainActor
private final class TestIconApplier: AppIconApplying {
  private(set) var appliedModes: [BruceMode] = []
  private let failingMode: BruceMode?
  private let error: TestIconError
  private let eventRecorder: TestEventRecorder?

  init(
    failingMode: BruceMode? = nil,
    error: TestIconError = .unavailable,
    eventRecorder: TestEventRecorder? = nil
  ) {
    self.failingMode = failingMode
    self.error = error
    self.eventRecorder = eventRecorder
  }

  func apply(_ mode: BruceMode) async throws {
    appliedModes.append(mode)
    eventRecorder?.events.append(.applyIcon(mode))
    if mode == failingMode {
      throw error
    }
  }
}

private enum TestIconError: Error {
  case unavailable
  case unsupported
}

@MainActor
private final class CancellingOnceIconApplier: AppIconApplying {
  private(set) var attemptCount = 0

  func apply(_ mode: BruceMode) async throws {
    attemptCount += 1
    if attemptCount == 1 {
      throw CancellationError()
    }
  }
}

private final class TestEventRecorder {
  var events: [TestEvent] = []
}

private enum TestEvent: Equatable {
  case applyIcon(BruceMode)
  case saveMode(BruceMode)
}

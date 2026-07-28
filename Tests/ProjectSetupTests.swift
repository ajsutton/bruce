import XCTest

@testable import Bruce

@MainActor
final class ProjectSetupTests: XCTestCase {
  func testBruceDefaultsToStandardWhenNoPreferenceExists() async {
    let store = TestModeStore()
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    await controller.restore()

    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(iconApplier.appliedModes, [.standard])
  }

  func testLocalStoreTreatsAbsentOrInvalidValuesAsUnset() {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated user defaults.")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = BruceModeStore(defaults: defaults)

    XCTAssertNil(store.loadMode())

    defaults.set("not-a-bruce-mode", forKey: BruceMode.storageKey)
    XCTAssertNil(store.loadMode())
  }

  func testLocalStoreSavesModeOnThisDevice() {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated user defaults.")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = BruceModeStore(defaults: defaults)

    store.saveMode(.full)

    XCTAssertEqual(store.loadMode(), .full)
  }

  func testRefreshingLocalPreferenceAppliesSystemSettingsChange() async {
    let store = TestModeStore(localMode: .standard)
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.restore()
    store.localMode = .full

    await controller.refreshLocalPreference()

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(iconApplier.appliedModes, [.standard, .full])
  }

  func testPersistedFullBruceIsRestoredAfterItsIconIsApplied() async {
    let store = TestModeStore(localMode: .full)
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    XCTAssertEqual(controller.mode, .standard)
    await controller.restore()

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(iconApplier.appliedModes, [.full])
  }

  func testCancelledRestorationPreservesPreferenceAndCanRetry() async {
    let store = TestModeStore(localMode: .full)
    let iconApplier = CancellingOnceIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    await controller.restore()

    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(store.localMode, .full)
    XCTAssertFalse(controller.hasAppIconError)

    await controller.restore()

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(iconApplier.attemptCount, 2)
  }

  func testSelectingFullBruceAppliesItsIconBeforePersistingTheMode() async {
    let eventRecorder = TestEventRecorder()
    let store = TestModeStore(eventRecorder: eventRecorder)
    let iconApplier = TestIconApplier(eventRecorder: eventRecorder)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.restore()

    await controller.select(.full)

    XCTAssertEqual(
      eventRecorder.events,
      [.applyIcon(.standard), .applyIcon(.full), .saveMode(.full)]
    )
    XCTAssertEqual(store.localMode, .full)
    XCTAssertEqual(controller.mode, .full)
  }

  func testSelectionBeforeRestorationRemainsTheNewestRequest() async {
    let store = TestModeStore(localMode: .standard)
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    controller.requestSelection(.full)
    await controller.restore()

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(store.localMode, .full)
  }

  func testIconFailureKeepsTheCurrentCoordinatedMode() async {
    let store = TestModeStore()
    let iconApplier = TestIconApplier(failingMode: .full, error: .unavailable)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.restore()

    await controller.select(.full)

    XCTAssertEqual(store.localMode, .standard)
    XCTAssertEqual(controller.mode, .standard)
    XCTAssertTrue(controller.hasAppIconError)
  }

  func testUnsupportedFullBruceIconKeepsStandardMode() async {
    let store = TestModeStore()
    let iconApplier = TestIconApplier(failingMode: .full, error: .unsupported)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.restore()

    await controller.select(.full)

    XCTAssertFalse(controller.mode.isFullBruce)
  }

  func testNewSelectionReplacesOneWaitingForItsIcon() async {
    let store = TestModeStore()
    let didSuspend = expectation(description: "Full Bruce icon application suspended")
    let iconApplier = SuspendingIconApplier(suspendingMode: .full, didSuspend: didSuspend)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.restore()

    controller.requestSelection(.full)
    await fulfillment(of: [didSuspend], timeout: 1)
    controller.requestSelection(.standard)
    iconApplier.resume()
    await controller.waitForTransitions()

    XCTAssertEqual(iconApplier.appliedModes, [.standard, .full, .standard])
    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(store.localMode, .standard)
  }

  func testSystemSettingsChangeReplacesPendingSelection() async {
    let store = TestModeStore()
    let didSuspend = expectation(description: "Full Bruce icon application suspended")
    let iconApplier = SuspendingIconApplier(suspendingMode: .full, didSuspend: didSuspend)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.restore()

    controller.requestSelection(.full)
    await fulfillment(of: [didSuspend], timeout: 1)
    store.localMode = .standard
    controller.requestLocalPreferenceRefresh()
    iconApplier.resume()
    await controller.waitForTransitions()

    XCTAssertEqual(iconApplier.appliedModes, [.standard, .full, .standard])
    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(store.localMode, .standard)
  }

  func testConcurrentRestorationWaitsForTheSharedTransition() async {
    let store = TestModeStore(localMode: .full)
    let didSuspend = expectation(description: "Full Bruce icon application suspended")
    let iconApplier = SuspendingIconApplier(suspendingMode: .full, didSuspend: didSuspend)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    let firstRestoration = Task { @MainActor in
      await controller.restore()
    }
    await fulfillment(of: [didSuspend], timeout: 1)
    firstRestoration.cancel()
    let secondRestoration = Task { @MainActor in
      await controller.restore()
    }
    iconApplier.resume()
    await secondRestoration.value

    XCTAssertEqual(controller.mode, .full)
    XCTAssertFalse(controller.isTransitioning)
  }
}

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

  func testSyncedStoreTreatsAbsentOrInvalidLocalValuesAsUnset() {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated user defaults.")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SyncedBruceModeStore(
      defaults: defaults,
      ubiquitousStore: TestUbiquitousStore()
    )

    XCTAssertNil(store.loadLocalMode())

    defaults.set("not-a-bruce-mode", forKey: BruceMode.storageKey)
    XCTAssertNil(store.loadLocalMode())
  }

  func testSyncedStoreSavesModeLocallyAndInUbiquitousPreferences() {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated user defaults.")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let ubiquitousStore = TestUbiquitousStore()
    let store = SyncedBruceModeStore(
      defaults: defaults,
      ubiquitousStore: ubiquitousStore
    )

    store.saveMode(.full)

    XCTAssertEqual(store.loadLocalMode(), .full)
    XCTAssertEqual(store.loadSyncedMode(), .full)
  }

  func testSyncedStoreDetectsAChangeMadeBySystemSettings() {
    let suiteName = "BruceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated user defaults.")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SyncedBruceModeStore(
      defaults: defaults,
      ubiquitousStore: TestUbiquitousStore()
    )
    store.saveMode(.standard)

    defaults.set(true, forKey: BruceMode.storageKey)

    XCTAssertTrue(store.hasUnpublishedLocalChange())
    XCTAssertEqual(store.loadLocalMode(), .full)
    XCTAssertEqual(store.loadSyncedMode(), .standard)
  }

  func testSyncedPreferenceWinsDuringInitialSynchronization() async {
    let store = TestModeStore(localMode: .standard, syncedMode: .full)
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    await controller.synchronize()

    XCTAssertTrue(store.didPrepareForSynchronization)
    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(store.localMode, .full)
  }

  func testSystemSettingsChangeWinsOverStaleSyncedPreferenceAtLaunch() async {
    let store = TestModeStore(
      localMode: .full,
      syncedMode: .standard,
      hasUnpublishedLocalChange: true
    )
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    await controller.synchronize()

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(store.syncedMode, .full)
  }

  func testRefreshingLocalPreferencePublishesItForOtherDevices() async {
    let store = TestModeStore(localMode: .standard)
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.synchronize()
    store.localMode = .full

    await controller.refreshLocalPreference()

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(store.syncedMode, .full)
  }

  func testRefreshingSyncedPreferenceUpdatesTheLocalCopy() async {
    let store = TestModeStore(localMode: .standard)
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.synchronize()
    store.syncedMode = .full

    await controller.refreshSyncedPreference()

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(store.localMode, .full)
  }

  func testPersistedFullBruceIsRestoredAfterItsIconIsApplied() async {
    let store = TestModeStore(localMode: .full)
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    XCTAssertEqual(controller.mode, .standard)
    await controller.synchronize()

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(iconApplier.appliedModes, [.full])
  }

  func testCancelledSynchronizationPreservesPreferenceAndCanRetry() async {
    let store = TestModeStore(localMode: .full)
    let iconApplier = CancellingOnceIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    await controller.synchronize()

    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(store.localMode, .full)
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
    XCTAssertEqual(store.localMode, .full)
    XCTAssertEqual(controller.mode, .full)
  }

  func testSelectionBeforeSynchronizationRemainsTheNewestRequest() async {
    let store = TestModeStore(localMode: .standard)
    let iconApplier = TestIconApplier()
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    controller.requestSelection(.full)
    await controller.synchronize()

    XCTAssertEqual(controller.mode, .full)
    XCTAssertEqual(store.localMode, .full)
    XCTAssertEqual(store.syncedMode, .full)
  }

  func testIconFailureKeepsTheCurrentCoordinatedMode() async {
    let store = TestModeStore()
    let iconApplier = TestIconApplier(failingMode: .full, error: .unavailable)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.synchronize()

    await controller.select(.full)

    XCTAssertEqual(store.localMode, .standard)
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

  func testNewSelectionReplacesOneWaitingForItsIcon() async {
    let store = TestModeStore()
    let didSuspend = expectation(description: "Full Bruce icon application suspended")
    let iconApplier = SuspendingIconApplier(suspendingMode: .full, didSuspend: didSuspend)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.synchronize()

    controller.requestSelection(.full)
    await fulfillment(of: [didSuspend], timeout: 1)
    controller.requestSelection(.standard)
    iconApplier.resume()
    await controller.waitForTransitions()

    XCTAssertEqual(iconApplier.appliedModes, [.standard, .full, .standard])
    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(store.localMode, .standard)
    XCTAssertEqual(store.syncedMode, .standard)
  }

  func testSyncedChangeReplacesLocalChangeWaitingForItsIcon() async {
    let store = TestModeStore()
    let didSuspend = expectation(description: "Full Bruce icon application suspended")
    let iconApplier = SuspendingIconApplier(suspendingMode: .full, didSuspend: didSuspend)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.synchronize()

    controller.requestSelection(.full)
    await fulfillment(of: [didSuspend], timeout: 1)
    store.syncedMode = .standard
    store.sendSyncedPreferenceChange()
    iconApplier.resume()
    await controller.waitForTransitions()

    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(store.localMode, .standard)
    XCTAssertEqual(store.syncedMode, .standard)
  }

  func testSystemSettingsChangeMatchingPublishedModeReplacesPendingSelection() async {
    let store = TestModeStore()
    let didSuspend = expectation(description: "Full Bruce icon application suspended")
    let iconApplier = SuspendingIconApplier(suspendingMode: .full, didSuspend: didSuspend)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.synchronize()

    controller.requestSelection(.full)
    await fulfillment(of: [didSuspend], timeout: 1)
    store.setLocalModeFromSystemSettings(.standard)
    controller.requestLocalPreferenceRefresh()
    iconApplier.resume()
    await controller.waitForTransitions()

    XCTAssertEqual(iconApplier.appliedModes, [.standard, .full, .standard])
    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(store.syncedMode, .standard)
  }

  func testSyncedNotificationDoesNotOverrideUnpublishedSystemSettingsChange() async {
    let store = TestModeStore()
    let didSuspend = expectation(description: "Full Bruce icon application suspended")
    let iconApplier = SuspendingIconApplier(suspendingMode: .full, didSuspend: didSuspend)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)
    await controller.synchronize()

    controller.requestSelection(.full)
    await fulfillment(of: [didSuspend], timeout: 1)
    store.setLocalModeFromSystemSettings(.standard)
    store.syncedMode = .full
    store.sendSyncedPreferenceChange()
    iconApplier.resume()
    await controller.waitForTransitions()

    XCTAssertEqual(iconApplier.appliedModes, [.standard, .full, .standard])
    XCTAssertEqual(controller.mode, .standard)
    XCTAssertEqual(store.syncedMode, .standard)
  }

  func testConcurrentSynchronizationWaitsForTheSharedTransition() async {
    let store = TestModeStore(localMode: .full)
    let didSuspend = expectation(description: "Full Bruce icon application suspended")
    let iconApplier = SuspendingIconApplier(suspendingMode: .full, didSuspend: didSuspend)
    let controller = BruceModeController(store: store, iconApplier: iconApplier)

    let firstSynchronization = Task { @MainActor in
      await controller.synchronize()
    }
    await fulfillment(of: [didSuspend], timeout: 1)
    firstSynchronization.cancel()
    let secondSynchronization = Task { @MainActor in
      await controller.synchronize()
    }
    iconApplier.resume()
    await secondSynchronization.value

    XCTAssertEqual(controller.mode, .full)
    XCTAssertFalse(controller.isTransitioning)
  }
}

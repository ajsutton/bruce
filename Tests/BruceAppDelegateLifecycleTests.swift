#if os(macOS)
  import AppKit
  import Foundation
  import XCTest

  @testable import Bruce

  @MainActor
  final class BruceAppDelegateLifecycleTests: XCTestCase {
    func testNewConnectionRejectsConnectionSupersededDuringReset() async {
      let loader = ObservationTestTemperatureLoader()
      loader.started.isInverted = true
      let reset = ControlledStateFeedReset()
      let coordinator = makeCoordinator(
        temperatureLoader: loader,
        resetStateFeed: reset.call
      )
      let delegate = BruceAppDelegate()
      delegate.configure(
        setupStore: HomeAssistantSetupStore(discovery: ApplicationObservationDiscovery()),
        observationCoordinator: coordinator
      )

      delegate.synchronize(with: .ready(credentials))
      await fulfillment(of: [reset.started], timeout: 1)
      delegate.synchronize(with: .signedOut)
      reset.resume()

      await fulfillment(of: [loader.started], timeout: 0.1)
      XCTAssertEqual(loader.startCount, 0)
    }

    func testApplicationObservationSurvivesLastWindowClosing() async {
      let loader = ObservationTestTemperatureLoader()
      let coordinator = makeCoordinator(temperatureLoader: loader)
      let setupStore = HomeAssistantSetupStore(
        discovery: ApplicationObservationDiscovery(),
        connection: ApplicationObservationConnection(credentials: credentials)
      )
      let delegate = BruceAppDelegate()
      delegate.configure(
        setupStore: setupStore,
        observationCoordinator: coordinator
      )
      delegate.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification)
      )
      await fulfillment(of: [loader.started], timeout: 1)

      let windowRegistered = expectation(description: "Window observation registered")
      let windowObservation = Task { @MainActor in
        await coordinator.observeUpdates(
          while: true,
          registrationDidBegin: { windowRegistered.fulfill() }
        )
      }
      await fulfillment(of: [windowRegistered], timeout: 1)
      windowObservation.cancel()
      await windowObservation.value

      XCTAssertEqual(loader.cancellationCount, 0)
      XCTAssertEqual(loader.startCount, 1)
      let applicationObservationCancelled = loader.expectCancellationCount(1)
      setupStore.disconnect()
      await fulfillment(of: [applicationObservationCancelled], timeout: 1)

      delegate.applicationWillTerminate(
        Notification(name: NSApplication.willTerminateNotification)
      )
    }

    func testWakingMacRefreshesHomeAssistantStateFeed() async {
      let loader = ObservationTestTemperatureLoader()
      let refreshStarted = expectation(description: "State feed refresh started")
      let coordinator = makeCoordinator(
        temperatureLoader: loader,
        refreshStateFeed: {
          refreshStarted.fulfill()
          return true
        }
      )
      let setupStore = HomeAssistantSetupStore(
        discovery: ApplicationObservationDiscovery(),
        connection: ApplicationObservationConnection(credentials: credentials)
      )
      let delegate = BruceAppDelegate()
      delegate.configure(
        setupStore: setupStore,
        observationCoordinator: coordinator
      )
      delegate.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification)
      )
      await fulfillment(of: [loader.started], timeout: 1)

      NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.didWakeNotification,
        object: nil
      )

      await fulfillment(of: [refreshStarted], timeout: 1)
      delegate.applicationWillTerminate(
        Notification(name: NSApplication.willTerminateNotification)
      )
    }

    func testFailedConnectionRemovalRestartsApplicationObservation() async {
      let loader = ObservationTestTemperatureLoader()
      loader.started.assertForOverFulfill = false
      let coordinator = makeCoordinator(temperatureLoader: loader)
      let setupStore = HomeAssistantSetupStore(
        discovery: ApplicationObservationDiscovery(),
        connection: ApplicationObservationConnection(
          credentials: credentials,
          disconnectError: HomeAssistantCredentialStoreError.keychainFailure(-1)
        )
      )
      let delegate = BruceAppDelegate()
      delegate.configure(
        setupStore: setupStore,
        observationCoordinator: coordinator
      )
      delegate.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification)
      )
      await fulfillment(of: [loader.started], timeout: 1)
      let cancelled = loader.expectCancellationCount(1)
      let restarted = loader.expectStartCount(2)

      setupStore.disconnect()
      await fulfillment(of: [cancelled, restarted], timeout: 1)

      XCTAssertEqual(setupStore.connectionCheckState, .disconnectFailed)
      XCTAssertEqual(loader.startCount, 2)
      delegate.applicationWillTerminate(
        Notification(name: NSApplication.willTerminateNotification)
      )
    }

    private func makeCoordinator(
      temperatureLoader: ObservationTestTemperatureLoader,
      refreshStateFeed: @escaping @Sendable () async -> Bool = { false },
      resetStateFeed: @escaping @Sendable () async -> Void = {}
    ) -> HomeAssistantObservationCoordinator {
      HomeAssistantObservationCoordinator(
        temperatureStore: HomeAssistantTemperatureStore(loader: temperatureLoader),
        chargingStore: HomeAssistantEVChargingStore(client: ObservationTestChargingClient()),
        garageDoorStore: HomeAssistantGarageDoorStore(loader: TestGarageDoorLoader()),
        homeEnergyStore: HomeAssistantHomeEnergyStore(loader: ObservationTestEnergyLoader()),
        refreshStateFeed: refreshStateFeed,
        resetStateFeed: resetStateFeed
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

  private struct ApplicationObservationDiscovery: HomeAssistantDiscovering {
    func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
      AsyncThrowingStream { $0.finish() }
    }
  }

  @MainActor
  private final class ApplicationObservationConnection: HomeAssistantConnecting {
    private let credentials: HomeAssistantCredentials
    private let disconnectError: (any Error)?

    init(
      credentials: HomeAssistantCredentials,
      disconnectError: (any Error)? = nil
    ) {
      self.credentials = credentials
      self.disconnectError = disconnectError
    }

    func connect(
      to candidate: HomeAssistantConnectionCandidate
    ) async throws -> HomeAssistantCredentials {
      credentials
    }

    func restore() async throws -> HomeAssistantCredentials? { credentials }
    func testConnection() async throws -> HomeAssistantCredentials { credentials }
    func disconnect() async throws {
      if let disconnectError {
        throw disconnectError
      }
    }
    func cancel() {}
  }
#endif

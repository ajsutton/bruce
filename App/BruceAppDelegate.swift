#if os(iOS)
  import UIKit

  final class BruceAppDelegate: NSObject, UIApplicationDelegate {
    func application(
      _ application: UIApplication,
      configurationForConnecting connectingSceneSession: UISceneSession,
      options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
      let configuration = UISceneConfiguration(
        name: nil,
        sessionRole: connectingSceneSession.role
      )
      configuration.delegateClass = BruceSceneDelegate.self
      return configuration
    }
  }
#elseif os(macOS)
  import AppKit
  import Combine

  @MainActor
  final class BruceAppDelegate: NSObject, NSApplicationDelegate {
    private weak var setupStore: HomeAssistantSetupStore?
    private weak var observationCoordinator: HomeAssistantObservationCoordinator?
    private var connectionObservation: AnyCancellable?
    private var observationTask: Task<Void, Never>?
    private var restorationTask: Task<Void, Never>?
    private var synchronizationTask: Task<Void, Never>?
    private var wakeRecoveryTask: Task<Void, Never>?
    private var wakeObservation: AnyCancellable?
    private var synchronizationGeneration = UUID()

    func configure(
      setupStore: HomeAssistantSetupStore,
      observationCoordinator: HomeAssistantObservationCoordinator
    ) {
      self.setupStore = setupStore
      self.observationCoordinator = observationCoordinator
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
      guard
        observationTask == nil,
        restorationTask == nil,
        connectionObservation == nil,
        let setupStore,
        let observationCoordinator
      else { return }
      observationTask = Task {
        await observationCoordinator.observeUpdates(while: true)
      }
      wakeObservation = NSWorkspace.shared.notificationCenter
        .publisher(for: NSWorkspace.didWakeNotification)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          self?.sendConnectionWakeHint()
        }
      connectionObservation = setupStore.$step
        .map { [weak setupStore] step in
          HomeAssistantPresentation(
            step: step,
            connectionCheckState: setupStore?.connectionCheckState ?? .idle
          ).access
        }
        .removeDuplicates()
        .sink { [weak self] access in
          self?.synchronize(with: access)
        }
      restorationTask = Task {
        await setupStore.restoreSavedConnection()
      }
    }

    func applicationWillTerminate(_ notification: Notification) {
      wakeObservation = nil
      wakeRecoveryTask?.cancel()
      wakeRecoveryTask = nil
      connectionObservation = nil
      synchronizationGeneration = UUID()
      synchronizationTask?.cancel()
      synchronizationTask = nil
      restorationTask?.cancel()
      restorationTask = nil
      observationTask?.cancel()
      observationTask = nil
    }

    private func sendConnectionWakeHint() {
      guard wakeRecoveryTask == nil else { return }
      wakeRecoveryTask = Task { [weak self, weak observationCoordinator] in
        await observationCoordinator?.connectionDidWake()
        guard !Task.isCancelled else { return }
        self?.wakeRecoveryTask = nil
      }
    }

    func synchronize(with access: HomeAssistantAccessState) {
      let generation = UUID()
      synchronizationGeneration = generation
      synchronizationTask?.cancel()
      synchronizationTask = Task { [weak self, weak observationCoordinator] in
        await observationCoordinator?.synchronize(with: access)
        guard self?.synchronizationGeneration == generation else { return }
        self?.synchronizationTask = nil
      }
    }
  }
#endif

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
      connectionObservation = setupStore.$step
        .map { [weak setupStore] step in
          HomeAssistantPresentation(
            step: step,
            connectionCheckState: setupStore?.connectionCheckState ?? .idle
          ).connection
        }
        .removeDuplicates()
        .sink { [weak self] connection in
          self?.synchronize(with: connection)
        }
      restorationTask = Task {
        await setupStore.restoreSavedConnection()
      }
    }

    func applicationWillTerminate(_ notification: Notification) {
      connectionObservation = nil
      synchronizationGeneration = UUID()
      synchronizationTask?.cancel()
      synchronizationTask = nil
      restorationTask?.cancel()
      restorationTask = nil
      observationTask?.cancel()
      observationTask = nil
    }

    func synchronize(with connection: HomeAssistantConnectionState) {
      let generation = UUID()
      synchronizationGeneration = generation
      synchronizationTask?.cancel()
      synchronizationTask = Task { [weak self, weak observationCoordinator] in
        await observationCoordinator?.synchronize(with: connection)
        guard self?.synchronizationGeneration == generation else { return }
        self?.synchronizationTask = nil
      }
    }
  }
#endif

import Combine
import Foundation
import OSLog

@MainActor
final class BruceModeController: ObservableObject {
  @Published private(set) var mode = BruceMode.standard
  @Published private(set) var isTransitioning = false
  @Published var appIconErrorMessage: String?

  private let store: any BruceModeStoring
  private let iconApplier: any AppIconApplying
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Bruce",
    category: "BrandMode"
  )
  private var hasStarted = false
  private var lastAppliedIconMode: BruceMode?
  private var nextGeneration = 0
  private var pendingRequest: TransitionRequest?
  private var transitionTask: Task<Void, Never>?
  private var syncedPreferenceCancellable: AnyCancellable?

  init(
    store: any BruceModeStoring = SyncedBruceModeStore(),
    iconApplier: any AppIconApplying = AppIconController()
  ) {
    self.store = store
    self.iconApplier = iconApplier
    syncedPreferenceCancellable = store.syncedPreferenceChanges
      .receive(on: RunLoop.main)
      .sink { @MainActor [weak self] in
        self?.requestSyncedPreferenceRefresh()
      }
  }

  func synchronize() async {
    start()
    await waitForTransitions()
  }

  func select(_ selectedMode: BruceMode) async {
    requestSelection(selectedMode)
    await waitForTransitions()
  }

  func requestSelection(_ selectedMode: BruceMode) {
    if !hasStarted {
      start()
    }
    enqueue(selectedMode, persistence: .localAndSynced)
  }

  func refreshLocalPreference() async {
    requestLocalPreferenceRefresh()
    await waitForTransitions()
  }

  func refreshSyncedPreference() async {
    requestSyncedPreferenceRefresh()
    await waitForTransitions()
  }

  func requestLocalPreferenceRefresh() {
    guard hasStarted else {
      start()
      return
    }

    guard let localMode = store.loadLocalMode() else {
      store.prepareForSynchronization()
      return
    }
    if store.hasUnpublishedLocalChange() || localMode != mode {
      enqueue(localMode, persistence: .localAndSynced)
    } else {
      store.prepareForSynchronization()
    }
  }

  func waitForTransitions() async {
    while let transitionTask {
      await transitionTask.value
    }
  }

  private func start() {
    guard !hasStarted else {
      return
    }
    hasStarted = true
    store.prepareForSynchronization()

    if store.hasUnpublishedLocalChange(), let localMode = store.loadLocalMode() {
      enqueue(localMode, persistence: .localAndSynced, forceIconApplication: true, isInitial: true)
    } else if let syncedMode = store.loadSyncedMode() {
      enqueue(syncedMode, persistence: .local, forceIconApplication: true, isInitial: true)
    } else if let localMode = store.loadLocalMode() {
      enqueue(localMode, persistence: .localAndSynced, forceIconApplication: true, isInitial: true)
    } else {
      enqueue(.standard, persistence: .none, forceIconApplication: true, isInitial: true)
    }
  }

  private func requestSyncedPreferenceRefresh() {
    guard hasStarted else {
      start()
      return
    }
    if store.hasUnpublishedLocalChange(), let localMode = store.loadLocalMode() {
      enqueue(localMode, persistence: .localAndSynced)
      return
    }
    guard let syncedMode = store.loadSyncedMode() else {
      return
    }
    enqueue(syncedMode, persistence: .local)
  }

  private func enqueue(
    _ selectedMode: BruceMode,
    persistence: Persistence,
    forceIconApplication: Bool = false,
    isInitial: Bool = false
  ) {
    nextGeneration += 1
    pendingRequest = TransitionRequest(
      mode: selectedMode,
      persistence: persistence,
      forceIconApplication: forceIconApplication,
      isInitial: isInitial,
      generation: nextGeneration
    )

    guard transitionTask == nil else {
      return
    }

    isTransitioning = true
    transitionTask = Task { @MainActor [weak self] in
      await self?.processRequests()
    }
  }

  private func processRequests() async {
    while let request = pendingRequest {
      pendingRequest = nil
      await perform(request)
    }

    isTransitioning = false
    transitionTask = nil
  }

  private func perform(_ request: TransitionRequest) async {
    if request.mode == mode,
      lastAppliedIconMode == request.mode,
      !request.forceIconApplication
    {
      persist(request.mode, to: request.persistence)
      return
    }

    let previousMode = mode
    mode = request.mode

    do {
      try await iconApplier.apply(request.mode)
      lastAppliedIconMode = request.mode
      guard request.generation == nextGeneration else {
        return
      }
      persist(request.mode, to: request.persistence)
    } catch is CancellationError {
      guard request.generation == nextGeneration else {
        return
      }
      mode = previousMode
      if request.isInitial {
        hasStarted = false
      }
    } catch {
      guard request.generation == nextGeneration else {
        return
      }
      mode = previousMode
      logger.error(
        "Could not apply the selected Bruce app icon: \(String(describing: error), privacy: .private)"
      )
      persist(mode, to: request.persistence)
      appIconErrorMessage = "The current look is still active."
    }
  }

  private func persist(_ mode: BruceMode, to persistence: Persistence) {
    switch persistence {
    case .none:
      break
    case .local:
      store.saveLocalMode(mode)
    case .localAndSynced:
      store.saveMode(mode)
    }
  }

  private struct TransitionRequest {
    let mode: BruceMode
    let persistence: Persistence
    let forceIconApplication: Bool
    let isInitial: Bool
    let generation: Int
  }

  private enum Persistence {
    case none
    case local
    case localAndSynced
  }
}

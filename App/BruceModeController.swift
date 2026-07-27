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

  init(
    store: any BruceModeStoring = BruceModeStore(),
    iconApplier: any AppIconApplying = AppIconController()
  ) {
    self.store = store
    self.iconApplier = iconApplier
  }

  func restore() async {
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
    enqueue(selectedMode, shouldPersist: true)
  }

  func refreshLocalPreference() async {
    requestLocalPreferenceRefresh()
    await waitForTransitions()
  }

  func requestLocalPreferenceRefresh() {
    guard hasStarted else {
      start()
      return
    }

    guard let localMode = store.loadMode() else {
      return
    }
    if localMode != mode {
      enqueue(localMode, shouldPersist: true)
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

    if let localMode = store.loadMode() {
      enqueue(localMode, shouldPersist: true, forceIconApplication: true, isInitial: true)
    } else {
      enqueue(.standard, shouldPersist: false, forceIconApplication: true, isInitial: true)
    }
  }

  private func enqueue(
    _ selectedMode: BruceMode,
    shouldPersist: Bool,
    forceIconApplication: Bool = false,
    isInitial: Bool = false
  ) {
    nextGeneration += 1
    pendingRequest = TransitionRequest(
      mode: selectedMode,
      shouldPersist: shouldPersist,
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
      persistIfNeeded(request)
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
      persistIfNeeded(request)
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
      if request.shouldPersist {
        store.saveMode(mode)
      }
      appIconErrorMessage = "The current look is still active."
    }
  }

  private func persistIfNeeded(_ request: TransitionRequest) {
    if request.shouldPersist {
      store.saveMode(request.mode)
    }
  }

  private struct TransitionRequest {
    let mode: BruceMode
    let shouldPersist: Bool
    let forceIconApplication: Bool
    let isInitial: Bool
    let generation: Int
  }
}

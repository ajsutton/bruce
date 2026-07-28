import Foundation

@MainActor
final class HomeAssistantHomeEnergyStore: ObservableObject {
  @Published private(set) var snapshot: HomeAssistantHomeEnergySnapshot
  @Published private(set) var isLoading = false
  @Published private(set) var isLive: Bool
  @Published private(set) var isRefreshing = false
  @Published private(set) var showsProgress = false
  @Published private(set) var problem: Problem?

  private let loader: any HomeAssistantHomeEnergyLoading
  private let onAuthenticationRequired: @MainActor @Sendable () -> Void
  private let progressDelay: Duration
  private let progressSleep: @Sendable (Duration) async -> Void
  private var loadGeneration = UUID()
  private var progressTask: Task<Void, Never>?

  init(
    loader: any HomeAssistantHomeEnergyLoading,
    snapshot: HomeAssistantHomeEnergySnapshot = .unavailable,
    isLive: Bool = false,
    progressDelay: Duration = .milliseconds(500),
    progressSleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    },
    onAuthenticationRequired: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.loader = loader
    self.snapshot = snapshot
    self.isLive = isLive
    self.progressDelay = progressDelay
    self.progressSleep = progressSleep
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  deinit {
    progressTask?.cancel()
  }

  func synchronize(with connection: HomeAssistantConnectionState) async {
    switch connection {
    case .connected:
      await observeUpdates()
    case .disconnected:
      reset()
    case .connecting:
      invalidateLoad()
      problem = nil
    case .unavailable:
      invalidateLoad()
      if problem != .signInRequired {
        problem = .connectionNeedsManagement
      }
    }
  }

  func load() async {
    let generation = UUID()
    loadGeneration = generation
    isLoading = true
    isRefreshing = false
    problem = nil
    scheduleProgress(for: generation)

    do {
      let snapshot = try await loader.loadHomeEnergySnapshot()
      try Task.checkCancellation()
      guard loadGeneration == generation else { return }
      guard snapshot.hasReadings else {
        problem = .invalidResponse
        finishLoad(isLive: false)
        return
      }
      self.snapshot = snapshot
      problem = nil
      finishLoad(isLive: true)
    } catch is CancellationError {
      guard loadGeneration == generation else { return }
      finishLoad(isLive: false)
    } catch {
      guard loadGeneration == generation else { return }
      guard !Task.isCancelled, !Self.isCancellation(error) else {
        finishLoad(isLive: false)
        return
      }
      let loadProblem = Self.problem(for: error)
      problem = loadProblem
      finishLoad(isLive: false)
      if loadProblem == .signInRequired {
        onAuthenticationRequired()
      }
    }
  }

  private func observeUpdates() async {
    let generation = UUID()
    beginObservation(generation: generation)

    do {
      for try await update in loader.homeEnergyUpdates() {
        try Task.checkCancellation()
        guard loadGeneration == generation else { return }
        apply(update)
      }
      try Task.checkCancellation()
      guard loadGeneration == generation else { return }
      if loader.providesContinuousEnergyUpdates {
        finishLoad(isLive: false)
        problem = .connectionUnavailable
      } else {
        finishProgress()
      }
    } catch is CancellationError {
      guard loadGeneration == generation else { return }
      finishLoad(isLive: false)
    } catch {
      guard loadGeneration == generation else { return }
      guard !Task.isCancelled, !Self.isCancellation(error) else {
        finishLoad(isLive: false)
        return
      }
      let loadProblem = Self.problem(for: error)
      problem = loadProblem
      finishLoad(isLive: false)
      if loadProblem == .signInRequired {
        onAuthenticationRequired()
      }
    }
  }

  private func beginObservation(generation: UUID) {
    loadGeneration = generation
    let preservesRefreshPresentation = isRefreshing && problem == nil
    isLoading = !preservesRefreshPresentation
    guard !preservesRefreshPresentation else { return }
    isLive = false
    isRefreshing = false
    problem = nil
    scheduleProgress(for: generation)
  }

  private func apply(
    _ update: HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>
  ) {
    switch update {
    case .live(let snapshot):
      guard snapshot.hasReadings else {
        problem = .invalidResponse
        finishLoad(isLive: false)
        return
      }
      self.snapshot = snapshot
      problem = nil
      isRefreshing = false
      finishLoad(isLive: true)
    case .refreshing(let snapshot):
      if snapshot.hasReadings {
        self.snapshot = snapshot
      }
      problem = nil
      isLoading = false
      isLive = false
      isRefreshing = true
      finishProgress()
    case .reconnecting(let snapshot):
      if snapshot.hasReadings {
        self.snapshot = snapshot
      }
      problem = .reconnecting
      isRefreshing = false
      finishLoad(isLive: false)
    }
  }

  func reset() {
    loadGeneration = UUID()
    snapshot = .unavailable
    isLoading = false
    isLive = false
    isRefreshing = false
    finishProgress()
    problem = nil
  }

  private func invalidateLoad() {
    loadGeneration = UUID()
    isLoading = false
    isLive = false
    isRefreshing = false
    finishProgress()
  }

  private func scheduleProgress(for generation: UUID) {
    finishProgress()
    progressTask = Task { [weak self, progressDelay, progressSleep] in
      await progressSleep(progressDelay)
      guard !Task.isCancelled else { return }
      guard let self, self.loadGeneration == generation, self.isLoading else { return }
      self.isLive = false
      self.showsProgress = true
    }
  }

  private func finishLoad(isLive: Bool) {
    isLoading = false
    self.isLive = isLive
    isRefreshing = false
    finishProgress()
  }

  private func finishProgress() {
    progressTask?.cancel()
    progressTask = nil
    showsProgress = false
  }
}

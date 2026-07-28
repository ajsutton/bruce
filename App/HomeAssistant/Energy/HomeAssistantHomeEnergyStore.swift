import Foundation

@MainActor
final class HomeAssistantHomeEnergyStore: ObservableObject {
  @Published private(set) var snapshot: HomeAssistantHomeEnergySnapshot
  @Published private(set) var isLoading = false
  @Published private(set) var isLive: Bool
  @Published private(set) var showsProgress = false
  @Published private(set) var problem: Problem?

  private let loader: any HomeAssistantHomeEnergyLoading
  private let onAuthenticationRequired: @MainActor @Sendable () -> Void
  private let progressDelay: Duration
  private let refreshInterval: Duration
  private let progressSleep: @Sendable (Duration) async -> Void
  private let refreshSleep: @Sendable (Duration) async throws -> Void
  private var loadGeneration = UUID()
  private var isConnected = false
  private var progressTask: Task<Void, Never>?

  init(
    loader: any HomeAssistantHomeEnergyLoading,
    snapshot: HomeAssistantHomeEnergySnapshot = .unavailable,
    isLive: Bool = false,
    progressDelay: Duration = .milliseconds(500),
    refreshInterval: Duration = .seconds(15),
    progressSleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    },
    refreshSleep: @escaping @Sendable (Duration) async throws -> Void = {
      try await Task.sleep(for: $0)
    },
    onAuthenticationRequired: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.loader = loader
    self.snapshot = snapshot
    self.isLive = isLive
    self.progressDelay = progressDelay
    self.refreshInterval = refreshInterval
    self.progressSleep = progressSleep
    self.refreshSleep = refreshSleep
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  deinit {
    progressTask?.cancel()
  }

  func synchronize(with connection: HomeAssistantConnectionState) async {
    switch connection {
    case .connected:
      isConnected = true
      await load()
    case .disconnected:
      isConnected = false
      reset()
    case .connecting:
      isConnected = false
      invalidateLoad()
      problem = nil
    case .unavailable:
      isConnected = false
      invalidateLoad()
      if problem != .signInRequired {
        problem = .connectionNeedsManagement
      }
    }
  }

  func monitor() async {
    while !Task.isCancelled {
      if isConnected, !isLoading {
        await load(preservingProblem: true)
      }
      do {
        try await refreshSleep(refreshInterval)
      } catch {
        return
      }
    }
  }

  func load() async {
    await load(preservingProblem: false)
  }

  private func load(preservingProblem: Bool) async {
    let generation = UUID()
    loadGeneration = generation
    isLoading = true
    if !preservingProblem {
      problem = nil
    }
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

  func reset() {
    loadGeneration = UUID()
    snapshot = .unavailable
    isLoading = false
    isLive = false
    finishProgress()
    problem = nil
  }

  private func invalidateLoad() {
    loadGeneration = UUID()
    isLoading = false
    isLive = false
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
    finishProgress()
  }

  private func finishProgress() {
    progressTask?.cancel()
    progressTask = nil
    showsProgress = false
  }
}

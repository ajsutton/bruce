import Foundation

@MainActor
final class HomeAssistantHomeEnergyStore: ObservableObject {
  @Published private(set) var snapshot: HomeAssistantHomeEnergySnapshot
  @Published private(set) var isLoading = false
  @Published private(set) var isLive: Bool
  @Published private(set) var isRefreshing = false
  @Published private(set) var showsProgress = false
  @Published private(set) var problem: Problem?

  let flowHistoryStore: HomeEnergyFlowHistoryStore
  let batteryHistoryStore: HomeEnergyBatteryHistoryStore
  let priceHistoryStore: HomeEnergyPriceHistoryStore

  private let loader: any HomeAssistantHomeEnergyLoading
  private let now: @Sendable () -> Date
  private let onAuthenticationRequired: @MainActor @Sendable () -> Void
  private let progressDelay: Duration
  private let progressSleep: @Sendable (Duration) async -> Void
  private var loadGeneration = UUID()
  private var progressTask: Task<Void, Never>?
  private var needsHistoryBackfill = false

  init(
    loader: any HomeAssistantHomeEnergyLoading,
    snapshot: HomeAssistantHomeEnergySnapshot = .unavailable,
    isLive: Bool = false,
    flowHistory: HomeEnergyFlowHistory = .empty,
    batteryHistory: HomeEnergyBatteryHistory = .empty,
    priceHistory: HomeEnergyPriceHistory = .empty,
    progressDelay: Duration = .milliseconds(500),
    progressSleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    },
    historySampleInterval: TimeInterval = HomeEnergyHistorySampling.interval,
    historySampleSleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    },
    onAuthenticationRequired: @escaping @MainActor @Sendable () -> Void = {},
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.loader = loader
    self.snapshot = snapshot
    self.isLive = isLive
    flowHistoryStore = HomeEnergyFlowHistoryStore(
      loader: loader,
      flowHistory: flowHistory,
      progressDelay: progressDelay,
      progressSleep: progressSleep,
      sampleInterval: historySampleInterval,
      sampleSleep: historySampleSleep
    )
    batteryHistoryStore = HomeEnergyBatteryHistoryStore(
      loader: loader,
      batteryHistory: batteryHistory,
      progressDelay: progressDelay,
      progressSleep: progressSleep,
      sampleInterval: historySampleInterval,
      sampleSleep: historySampleSleep
    )
    priceHistoryStore = HomeEnergyPriceHistoryStore(
      loader: loader,
      priceHistory: priceHistory,
      progressDelay: progressDelay,
      progressSleep: progressSleep,
      sampleInterval: historySampleInterval,
      sampleSleep: historySampleSleep
    )
    self.progressDelay = progressDelay
    self.progressSleep = progressSleep
    self.onAuthenticationRequired = onAuthenticationRequired
    self.now = now
    flowHistoryStore.authenticationFailureHandler = { [weak self] in
      self?.handleHistoryAuthenticationFailure()
    }
    batteryHistoryStore.authenticationFailureHandler = { [weak self] in
      self?.handleHistoryAuthenticationFailure()
    }
    priceHistoryStore.authenticationFailureHandler = { [weak self] in
      self?.handleHistoryAuthenticationFailure()
    }
  }

  deinit {
    progressTask?.cancel()
  }

  func synchronize(with connection: HomeAssistantConnectionState) async {
    switch connection {
    case .connected:
      let generation = UUID()
      beginObservation(generation: generation)
      reloadHistory()
      await observeUpdates(generation: generation)
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
}

extension HomeAssistantHomeEnergyStore {
  private func observeUpdates(generation: UUID) async {
    do {
      let updates = loader.homeEnergyUpdates()
      defer { updates.cancel() }
      for try await update in updates {
        try Task.checkCancellation()
        guard loadGeneration == generation else { return }
        apply(update)
      }
      try Task.checkCancellation()
      guard loadGeneration == generation else { return }
      if loader.providesContinuousEnergyUpdates {
        finishLoad(isLive: false)
        problem = .connectionUnavailable
        invalidateHistory()
      } else {
        finishProgress()
      }
    } catch is CancellationError {
      guard loadGeneration == generation else { return }
      invalidateHistory()
      finishLoad(isLive: false)
    } catch {
      guard loadGeneration == generation else { return }
      guard !Task.isCancelled, !Self.isCancellation(error) else {
        invalidateHistory()
        finishLoad(isLive: false)
        return
      }
      let loadProblem = Self.problem(for: error)
      problem = loadProblem
      finishLoad(isLive: false)
      invalidateHistory()
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
      publishSnapshotIfChanged(snapshot)
      let timestamp = now()
      if needsHistoryBackfill {
        needsHistoryBackfill = false
        reloadHistory()
      }
      recordHistory(snapshot: snapshot, at: timestamp)
      if problem != nil {
        problem = nil
      }
      if isRefreshing {
        isRefreshing = false
      }
      finishLoad(isLive: true)
    case .refreshing(let snapshot):
      if snapshot.hasReadings {
        publishSnapshotIfChanged(snapshot)
      }
      problem = nil
      isLoading = false
      isLive = false
      isRefreshing = true
      finishProgress()
      invalidateHistory()
      needsHistoryBackfill = true
    case .reconnecting(let snapshot):
      if snapshot.hasReadings {
        publishSnapshotIfChanged(snapshot)
      }
      problem = .reconnecting
      isRefreshing = false
      finishLoad(isLive: false)
      invalidateHistory()
      needsHistoryBackfill = true
    }
  }

  @discardableResult
  func reset() -> Task<Void, Never>? {
    loadGeneration = UUID()
    snapshot = .unavailable
    isLoading = false
    isLive = false
    isRefreshing = false
    finishProgress()
    problem = nil
    needsHistoryBackfill = false
    return resetHistory()
  }

  @discardableResult
  private func invalidateLoad() -> Task<Void, Never>? {
    loadGeneration = UUID()
    isLoading = false
    isLive = false
    isRefreshing = false
    finishProgress()
    needsHistoryBackfill = false
    return invalidateHistory()
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
    if isLoading {
      isLoading = false
    }
    if self.isLive != isLive {
      self.isLive = isLive
    }
    if isRefreshing {
      isRefreshing = false
    }
    finishProgress()
  }

  private func finishProgress() {
    progressTask?.cancel()
    progressTask = nil
    if showsProgress {
      showsProgress = false
    }
  }

  private func handleHistoryAuthenticationFailure() {
    guard problem != .signInRequired else { return }
    invalidateHistory()
    problem = .signInRequired
    finishLoad(isLive: false)
    onAuthenticationRequired()
  }

  private func publishSnapshotIfChanged(
    _ snapshot: HomeAssistantHomeEnergySnapshot
  ) {
    guard !self.snapshot.hasSamePresentation(as: snapshot) else { return }
    self.snapshot = snapshot
  }
}

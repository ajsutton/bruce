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
  private let publishWidgetSnapshot: @MainActor (HomeAssistantHomeEnergySnapshot, Date) -> Void
  private let onAuthenticationRequired: @MainActor @Sendable () -> Void
  private let progressDelay: Duration
  private let progressSleep: @Sendable (Duration) async -> Void
  private var loadGeneration = UUID()
  private var progressTask: Task<Void, Never>?
  private var needsHistoryBackfill = false
  private var canReuseHistoryAfterSuspension = false
  private var historyReuseDeadline: Date?

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
    publishWidgetSnapshot:
      @escaping @MainActor (HomeAssistantHomeEnergySnapshot, Date) -> Void = { _, _ in },
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
    self.publishWidgetSnapshot = publishWidgetSnapshot
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

  func synchronize(
    with access: HomeAssistantAccessState,
    historyReuseDeadline: Date? = nil
  ) async {
    switch access.phase {
    case .ready:
      let reusesHistory =
        historyReuseDeadline.map { now() < $0 } == true
        && canReuseHistoryAfterSuspension
        && hasUsableHistory
      let generation = UUID()
      beginObservation(generation: generation)
      if reusesHistory {
        self.historyReuseDeadline = historyReuseDeadline
      } else {
        reloadHistoryDiscardingReuse()
      }
      await observeUpdates(generation: generation)
    case .signedOut:
      reset()
    case .loading:
      invalidateLoad()
      problem = nil
    case .requiresUserAction:
      invalidateLoad()
      if problem != .signInRequired {
        problem = .connectionNeedsManagement
      }
    }
  }

  func prepareForActivitySuspension() {
    canReuseHistoryAfterSuspension = hasCurrentHistory
    historyReuseDeadline = nil
    invalidateHistory()
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
      publishWidgetSnapshot(snapshot, now())
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
      cancelObservation(generation: generation)
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
    historyReuseDeadline = nil
    let preservesRefreshPresentation = isRefreshing && problem == nil
    isLoading = !preservesRefreshPresentation
    guard !preservesRefreshPresentation else { return }
    isLive = false
    isRefreshing = false
    problem = nil
    scheduleProgress(for: generation)
  }

  private func cancelObservation(generation: UUID) {
    guard loadGeneration == generation else { return }
    historyReuseDeadline = nil
    invalidateHistory()
    finishLoad(isLive: false)
  }

  private func apply(
    _ update: HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>
  ) {
    switch update {
    case .live(let snapshot):
      applyLive(snapshot)
    case .refreshing(let snapshot):
      applyRefreshing(snapshot)
    case .reconnecting(let snapshot):
      applyReconnecting(snapshot)
    }
  }

  private func applyLive(_ snapshot: HomeAssistantHomeEnergySnapshot) {
    guard snapshot.hasReadings else {
      problem = .invalidResponse
      finishLoad(isLive: false)
      return
    }
    let timestamp = now()
    publishSnapshotIfChanged(snapshot)
    publishWidgetSnapshot(snapshot, timestamp)
    let validatesPreservedHistory =
      historyReuseDeadline.map { timestamp < $0 } == true
      && !needsHistoryBackfill
    let reloadsHistory =
      needsHistoryBackfill
      || (historyReuseDeadline != nil && !validatesPreservedHistory)
    if reloadsHistory {
      needsHistoryBackfill = false
      reloadHistoryDiscardingReuse()
    }
    recordHistory(snapshot: snapshot, at: timestamp)
    if validatesPreservedHistory {
      discardHistoryReuse()
      validatePreservedHistory()
    }
    if problem != nil {
      problem = nil
    }
    if isRefreshing {
      isRefreshing = false
    }
    finishLoad(isLive: true)
  }

  private func applyRefreshing(_ snapshot: HomeAssistantHomeEnergySnapshot) {
    if snapshot.hasReadings {
      publishSnapshotIfChanged(snapshot)
    }
    problem = nil
    isLoading = false
    isLive = false
    isRefreshing = true
    finishProgress()
    invalidateHistory()
    if !canStillReuseHistory {
      discardHistoryReuse()
      needsHistoryBackfill = true
    }
  }

  private func applyReconnecting(_ snapshot: HomeAssistantHomeEnergySnapshot) {
    if snapshot.hasReadings {
      publishSnapshotIfChanged(snapshot)
    }
    problem = .reconnecting
    isRefreshing = false
    finishLoad(isLive: false)
    discardHistoryReuse()
    invalidateHistory()
    needsHistoryBackfill = true
  }

  @discardableResult
  func reset() -> Task<Void, Never>? {
    loadGeneration = UUID()
    canReuseHistoryAfterSuspension = false
    historyReuseDeadline = nil
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
    canReuseHistoryAfterSuspension = false
    historyReuseDeadline = nil
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

  private var canStillReuseHistory: Bool {
    historyReuseDeadline.map { now() < $0 } == true
      && canReuseHistoryAfterSuspension
  }

  private func reloadHistoryDiscardingReuse() {
    discardHistoryReuse()
    reloadHistory()
  }

  private func discardHistoryReuse() {
    canReuseHistoryAfterSuspension = false
    historyReuseDeadline = nil
  }

  private func publishSnapshotIfChanged(
    _ snapshot: HomeAssistantHomeEnergySnapshot
  ) {
    guard !self.snapshot.hasSamePresentation(as: snapshot) else { return }
    self.snapshot = snapshot
  }
}

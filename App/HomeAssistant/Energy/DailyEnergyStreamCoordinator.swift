import Foundation
import OSLog

actor DailyEnergyStreamCoordinator {
  typealias Update =
    HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.symphonious.bruce",
    category: "HomeAssistantEnergy"
  )

  private let loader: (any HomeAssistantDailyEnergyTotalsLoading)?
  private let now: @Sendable () -> Date
  private let sleepUntil: @Sendable (Date) async throws -> Void
  private let requestTimeout: Duration
  private let yield: @Sendable (Update) -> Void
  private let finishUpdates: @Sendable ((any Error)?) -> Void
  private let cancelStates: @Sendable () -> Void

  private var refreshState = HomeAssistantDailyEnergyRefreshState()
  private var latestSnapshot: HomeAssistantHomeEnergySnapshot?
  private var refreshTask: Task<Void, Never>?
  private var refreshGeneration: UUID?
  private var wakeTask: Task<Void, Never>?
  private var wakeGeneration: UUID?
  private var importStatus: HomeAssistantDailyEnergyMetricStatus = .refreshing
  private var feedInStatus: HomeAssistantDailyEnergyMetricStatus = .refreshing
  private var retriedExpiredResult = false
  private var isFinished = false

  init(
    loader: (any HomeAssistantDailyEnergyTotalsLoading)?,
    now: @escaping @Sendable () -> Date,
    sleepUntil: @escaping @Sendable (Date) async throws -> Void,
    requestTimeout: Duration,
    yield: @escaping @Sendable (Update) -> Void,
    finish: @escaping @Sendable ((any Error)?) -> Void,
    cancelStates: @escaping @Sendable () -> Void
  ) {
    self.loader = loader
    self.now = now
    self.sleepUntil = sleepUntil
    self.requestTimeout = requestTimeout
    self.yield = yield
    finishUpdates = finish
    self.cancelStates = cancelStates
    let initialStatus: HomeAssistantDailyEnergyMetricStatus =
      loader == nil ? .current : .refreshing
    importStatus = initialStatus
    feedInStatus = initialStatus
  }

  func handle(_ update: HomeAssistantStateUpdate) {
    guard !isFinished else { return }
    let snapshot = HomeAssistantHomeEnergySnapshot(states: update.states)
    latestSnapshot = snapshot
    guard update.phase == .live else {
      refreshState.noteControlTransition()
      cancelRefresh()
      cancelWake()
      retriedExpiredResult = false
      setTransitionStatus()
      yield(
        Self.controlUpdate(
          phase: update.phase,
          snapshot: snapshot.replacingDailyTotals(
            refreshState.totals(adjustedFor: snapshot, at: now()),
            importStatus: importStatus,
            feedInStatus: feedInStatus
          )
        )
      )
      return
    }

    let timestamp = now()
    let shouldRefresh =
      loader != nil
      && refreshState.shouldRefresh(for: snapshot, at: timestamp)
    if shouldRefresh {
      if refreshTask != nil, refreshState.detectedDiscontinuity {
        cancelRefresh()
      }
      if refreshTask == nil {
        retriedExpiredResult = false
        startRefresh()
      }
    }
    let totals = refreshState.totals(
      adjustedFor: snapshot,
      at: timestamp
    )
    yield(
      .live(
        snapshot.replacingDailyTotals(
          totals,
          importStatus: importStatus,
          feedInStatus: feedInStatus
        )
      )
    )
  }

  func finish(throwing error: (any Error)? = nil) {
    guard !isFinished else { return }
    isFinished = true
    cancelRefresh()
    cancelWake()
    finishUpdates(error)
  }

  private func startRefresh() {
    guard let loader else { return }
    cancelWake()
    let generation = UUID()
    refreshGeneration = generation
    if refreshState.needsImportRefresh {
      importStatus = .refreshing
    }
    if refreshState.needsFeedInRefresh {
      feedInStatus = .refreshing
    }
    let requestTimeout = requestTimeout
    refreshTask = Task {
      do {
        let totals = try await Self.load(
          from: loader,
          timeout: requestTimeout
        )
        try Task.checkCancellation()
        refreshSucceeded(totals, generation: generation)
      } catch is CancellationError {
        return
      } catch {
        refreshFailed(error, generation: generation)
      }
    }
  }

  private func refreshSucceeded(
    _ totals: HomeAssistantDailyEnergyTotals,
    generation: UUID
  ) {
    guard !isFinished, refreshGeneration == generation,
      let latestSnapshot
    else {
      return
    }
    let timestamp = now()
    guard
      totals.interval.start <= timestamp
        && timestamp < totals.interval.end
    else {
      retryExpiredResult(generation: generation)
      return
    }
    refreshTask = nil
    refreshGeneration = nil
    retriedExpiredResult = false
    refreshState.noteSuccess(
      totals,
      snapshot: latestSnapshot,
      at: timestamp
    )
    importStatus =
      if refreshState.needsImportRefresh {
        refreshState.isRecoveringImportReset ? .refreshing : .failed
      } else {
        refreshState.hasPresentableImportCost ? .current : .failed
      }
    feedInStatus =
      if refreshState.needsFeedInRefresh {
        refreshState.isRecoveringFeedInReset ? .refreshing : .failed
      } else {
        refreshState.hasPresentableFeedInEarnings ? .current : .failed
      }
    yieldLatestSnapshot()
    scheduleWake()
  }

  private func refreshFailed(
    _ error: any Error,
    generation: UUID
  ) {
    guard !isFinished, refreshGeneration == generation else {
      return
    }
    refreshTask = nil
    refreshGeneration = nil
    if let apiError = error as? HomeAssistantAPIError,
      Self.isAuthenticationFailure(apiError)
    {
      isFinished = true
      finishUpdates(apiError)
      cancelStates()
      return
    }
    refreshState.noteFailure(at: now())
    if refreshState.needsImportRefresh {
      importStatus = .failed
    }
    if refreshState.needsFeedInRefresh {
      feedInStatus = .failed
    }
    Self.logger.error(
      "Couldn’t refresh today’s Home Assistant energy totals: \(String(describing: error), privacy: .private)"
    )
    yieldLatestSnapshot()
    scheduleWake()
  }

  private func retryExpiredResult(generation: UUID) {
    guard !retriedExpiredResult else {
      refreshFailed(
        HomeAssistantAPIError.invalidResponse,
        generation: generation
      )
      return
    }
    refreshTask = nil
    refreshGeneration = nil
    retriedExpiredResult = true
    startRefresh()
    yieldLatestSnapshot()
  }

  private func yieldLatestSnapshot() {
    guard let latestSnapshot else { return }
    yield(
      .live(
        latestSnapshot.replacingDailyTotals(
          refreshState.totals(
            adjustedFor: latestSnapshot,
            at: now()
          ),
          importStatus: importStatus,
          feedInStatus: feedInStatus
        )
      )
    )
  }

  private func cancelRefresh() {
    refreshGeneration = nil
    refreshTask?.cancel()
    refreshTask = nil
  }

  private func setTransitionStatus() {
    let status: HomeAssistantDailyEnergyMetricStatus =
      loader == nil ? .current : .refreshing
    importStatus = status
    feedInStatus = status
  }
}

extension DailyEnergyStreamCoordinator {
  fileprivate func scheduleWake() {
    cancelWake()
    guard let deadline = refreshState.nextRefreshDate(after: now()) else {
      return
    }
    let generation = UUID()
    wakeGeneration = generation
    wakeTask = Task {
      do {
        try await sleepUntil(deadline)
        try Task.checkCancellation()
        wake(generation: generation)
      } catch {
        return
      }
    }
  }

  fileprivate func wake(generation: UUID) {
    guard !isFinished, wakeGeneration == generation,
      let latestSnapshot
    else {
      return
    }
    wakeTask = nil
    wakeGeneration = nil
    let timestamp = now()
    guard
      refreshState.shouldRefresh(
        for: latestSnapshot,
        at: timestamp
      )
    else {
      scheduleWake()
      return
    }
    retriedExpiredResult = false
    startRefresh()
    yieldLatestSnapshot()
  }

  fileprivate func cancelWake() {
    wakeGeneration = nil
    wakeTask?.cancel()
    wakeTask = nil
  }

  nonisolated fileprivate static func load(
    from loader: any HomeAssistantDailyEnergyTotalsLoading,
    timeout: Duration
  ) async throws -> HomeAssistantDailyEnergyTotals {
    try await withThrowingTaskGroup(
      of: HomeAssistantDailyEnergyTotals.self
    ) { group in
      group.addTask {
        try await loader.loadDailyEnergyTotals()
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw URLError(.timedOut)
      }
      guard let first = try await group.next() else {
        throw HomeAssistantAPIError.invalidResponse
      }
      group.cancelAll()
      return first
    }
  }

  fileprivate static func controlUpdate(
    phase: HomeAssistantStateUpdate.Phase,
    snapshot: HomeAssistantHomeEnergySnapshot
  ) -> Update {
    switch phase {
    case .live:
      .live(snapshot)
    case .refreshing:
      .refreshing(snapshot)
    case .reconnecting:
      .reconnecting(snapshot)
    }
  }

  fileprivate static func isAuthenticationFailure(
    _ error: HomeAssistantAPIError
  ) -> Bool {
    switch error {
    case .noCredentials, .unauthorized, .reauthenticationRequired:
      true
    case .invalidServerURL, .incompatibleServer, .server, .invalidResponse,
      .staleOperation:
      false
    }
  }
}

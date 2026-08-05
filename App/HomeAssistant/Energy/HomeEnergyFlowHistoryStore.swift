import Combine
import Foundation

@MainActor
final class HomeEnergyFlowHistoryStore: ObservableObject {
  @Published private(set) var flowHistory: HomeEnergyFlowHistory
  @Published private(set) var hasUsableHistory: Bool
  @Published private(set) var isLoading = false
  @Published private(set) var isUnavailable = false
  @Published private(set) var isStale = false
  @Published private(set) var showsProgress = false
  @Published private(set) var problem: HomeEnergyHistoryLoadProblem?

  var authenticationFailureHandler: @MainActor @Sendable () -> Void = {}

  private let loader: any HomeAssistantHomeEnergyLoading
  private let progressDelay: Duration
  private let progressSleep: @Sendable (Duration) async -> Void
  private let sampleInterval: TimeInterval
  private let sampleSleep: @Sendable (Duration) async -> Void
  private var loadTask: Task<Void, Never>?
  private var progressTask: Task<Void, Never>?
  private var sampleTask: Task<Void, Never>?
  private var loadID = UUID()
  private var pendingHistory = HomeEnergyFlowHistory.empty
  private var queuedSample: QueuedSample?

  init(
    loader: any HomeAssistantHomeEnergyLoading,
    flowHistory: HomeEnergyFlowHistory = .empty,
    progressDelay: Duration = .milliseconds(500),
    progressSleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    },
    sampleInterval: TimeInterval = HomeEnergyHistorySampling.interval,
    sampleSleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    }
  ) {
    self.loader = loader
    self.flowHistory = flowHistory
    hasUsableHistory = flowHistory.hasCompleteSeries
    self.progressDelay = progressDelay
    self.progressSleep = progressSleep
    self.sampleInterval = sampleInterval
    self.sampleSleep = sampleSleep
  }

  deinit {
    loadTask?.cancel()
    progressTask?.cancel()
    sampleTask?.cancel()
  }

  func reload() {
    loadTask?.cancel()
    cancelQueuedSample()
    pendingHistory = .empty
    let requestID = UUID()
    loadID = requestID
    isLoading = true
    isUnavailable = false
    problem = nil
    scheduleProgress(for: requestID)

    let loader = loader
    loadTask = Task { [weak self, loader] in
      guard !Task.isCancelled else { return }
      do {
        let history = try await loader.loadHomeEnergyFlowHistory()
        try Task.checkCancellation()
        self?.publish(history, for: requestID)
      } catch {
        self?.publish(error, for: requestID)
      }
    }
  }

  func record(snapshot: HomeAssistantHomeEnergySnapshot, at timestamp: Date) {
    recordSample(snapshot: snapshot, at: timestamp)
  }

  func validatePreservedHistory() {
    guard hasUsableHistory else { return }
    isUnavailable = false
    isStale = false
  }

  @discardableResult
  func reset() -> Task<Void, Never>? {
    let cancelledTask = cancelLoad()
    cancelQueuedSample()
    flowHistory = .empty
    hasUsableHistory = false
    isUnavailable = true
    isStale = false
    problem = nil
    return cancelledTask
  }

  @discardableResult
  func invalidate() -> Task<Void, Never>? {
    let cancelledTask = cancelLoad()
    cancelQueuedSample()
    isUnavailable = !hasUsableHistory
    isStale = hasUsableHistory
    problem = nil
    return cancelledTask
  }

  private func publish(_ history: HomeEnergyFlowHistory, for requestID: UUID) {
    guard loadID == requestID, !Task.isCancelled else { return }
    if history.hasCompleteSeries {
      flowHistory = history.mergingLiveReadings(
        from: pendingHistoryIncludingQueuedSample()
      )
      hasUsableHistory = true
      isStale = false
    } else if hasUsableHistory {
      isStale = true
    }
    problem = nil
    isUnavailable = !hasUsableHistory
    finishLoad()
  }

  private func publish(_ error: any Error, for requestID: UUID) {
    guard loadID == requestID else { return }
    guard !Task.isCancelled, !HomeAssistantHomeEnergyStore.isCancellation(error) else {
      isUnavailable = !hasUsableHistory
      isStale = hasUsableHistory
      finishLoad()
      return
    }
    if HomeAssistantHomeEnergyStore.problem(for: error) == .signInRequired {
      authenticationFailureHandler()
      guard loadID == requestID else { return }
    }
    problem = .loadFailed
    isUnavailable = !hasUsableHistory
    isStale = hasUsableHistory
    finishLoad()
  }

  private func scheduleProgress(for requestID: UUID) {
    progressTask?.cancel()
    showsProgress = false
    guard !hasUsableHistory else { return }
    progressTask = Task { [weak self, progressDelay, progressSleep] in
      await progressSleep(progressDelay)
      guard !Task.isCancelled else { return }
      guard
        let self,
        self.loadID == requestID,
        self.isLoading,
        !self.hasUsableHistory
      else {
        return
      }
      self.showsProgress = true
    }
  }

  private func finishLoad() {
    progressTask?.cancel()
    progressTask = nil
    isLoading = false
    showsProgress = false
    pendingHistory = .empty
  }

  private func cancelLoad() -> Task<Void, Never>? {
    let cancelledTask = loadTask
    loadTask?.cancel()
    loadTask = nil
    loadID = UUID()
    finishLoad()
    return cancelledTask
  }
}

extension HomeEnergyFlowHistoryStore {
  fileprivate struct QueuedSample {
    let snapshot: HomeAssistantHomeEnergySnapshot
    let timestamp: Date
    let recordsPendingHistory: Bool
    let recordsPublishedHistory: Bool
  }

  fileprivate func recordSample(
    snapshot: HomeAssistantHomeEnergySnapshot,
    at timestamp: Date
  ) {
    promoteQueuedSampleForPendingAvailabilityTransition(to: snapshot)
    let recordsPendingHistory =
      isLoading
      && (pendingHistory == .empty
        || !shouldRecordImmediately(
          snapshot: snapshot,
          at: timestamp,
          in: pendingHistory
        ))
    if isLoading, !recordsPendingHistory {
      pendingHistory = pendingHistory.recording(
        snapshot: snapshot,
        at: timestamp
      )
    }

    let recordsPublishedHistory =
      hasUsableHistory
      && !shouldRecordImmediately(
        snapshot: snapshot,
        at: timestamp,
        in: flowHistory
      )
    if hasUsableHistory, !recordsPublishedHistory {
      flowHistory = flowHistory.recording(
        snapshot: snapshot,
        at: timestamp
      )
    }

    guard recordsPendingHistory || recordsPublishedHistory else {
      cancelQueuedSample()
      return
    }
    queuedSample = QueuedSample(
      snapshot: snapshot,
      timestamp: timestamp,
      recordsPendingHistory: recordsPendingHistory,
      recordsPublishedHistory: recordsPublishedHistory
    )
    scheduleQueuedSampleIfNeeded()
  }

  fileprivate func promoteQueuedSampleForPendingAvailabilityTransition(
    to snapshot: HomeAssistantHomeEnergySnapshot
  ) {
    guard
      isLoading,
      pendingHistory == .empty,
      let queuedSample,
      queuedSample.recordsPendingHistory,
      snapshot.hasFlowAvailabilityTransition(from: queuedSample.snapshot)
    else {
      return
    }
    sampleTask?.cancel()
    sampleTask = nil
    flushQueuedSample()
  }

  fileprivate func shouldRecordImmediately(
    snapshot: HomeAssistantHomeEnergySnapshot,
    at timestamp: Date,
    in history: HomeEnergyFlowHistory
  ) -> Bool {
    guard
      timestamp.timeIntervalSince(history.interval.end) < sampleInterval
    else {
      return true
    }
    return HomeEnergyFlowHistory.Series.allCases.contains { series in
      let latestIsAvailable =
        history.readings.last(where: { $0.series == series })?.kilowatts != nil
      return latestIsAvailable != (series.value(from: snapshot)?.isFinite == true)
    }
  }

  fileprivate func scheduleQueuedSampleIfNeeded() {
    guard sampleTask == nil, let queuedSample else { return }
    let delay = sampleDelay(for: queuedSample)
    let sampleSleep = sampleSleep
    sampleTask = Task { [weak self] in
      await sampleSleep(.seconds(delay))
      guard !Task.isCancelled else { return }
      self?.flushQueuedSample()
    }
  }

  fileprivate func sampleDelay(for sample: QueuedSample) -> TimeInterval {
    var delays: [TimeInterval] = []
    if sample.recordsPendingHistory {
      delays.append(
        pendingHistory == .empty
          ? sampleInterval
          : sampleInterval
            - sample.timestamp.timeIntervalSince(pendingHistory.interval.end)
      )
    }
    if sample.recordsPublishedHistory {
      delays.append(
        sampleInterval - sample.timestamp.timeIntervalSince(flowHistory.interval.end)
      )
    }
    return max(delays.min() ?? sampleInterval, 0)
  }

  fileprivate func flushQueuedSample() {
    sampleTask = nil
    guard let sample = queuedSample else { return }
    queuedSample = nil
    if sample.recordsPendingHistory, isLoading {
      pendingHistory = pendingHistory.recording(
        snapshot: sample.snapshot,
        at: sample.timestamp
      )
    }
    if sample.recordsPublishedHistory, hasUsableHistory {
      flowHistory = flowHistory.recording(
        snapshot: sample.snapshot,
        at: sample.timestamp
      )
    }
  }

  fileprivate func pendingHistoryIncludingQueuedSample() -> HomeEnergyFlowHistory {
    guard let sample = queuedSample, sample.recordsPendingHistory else {
      return pendingHistory
    }
    cancelQueuedSample()
    return pendingHistory.recording(
      snapshot: sample.snapshot,
      at: sample.timestamp
    )
  }

  fileprivate func cancelQueuedSample() {
    sampleTask?.cancel()
    sampleTask = nil
    queuedSample = nil
  }
}

extension HomeAssistantHomeEnergySnapshot {
  fileprivate func hasFlowAvailabilityTransition(from previous: Self) -> Bool {
    HomeEnergyFlowHistory.Series.allCases.contains { series in
      let currentIsAvailable = series.value(from: self)?.isFinite == true
      let previousIsAvailable = series.value(from: previous)?.isFinite == true
      return currentIsAvailable != previousIsAvailable
    }
  }
}

import Combine
import Foundation

@MainActor
final class ClimateHistoryStore: ObservableObject {
  @Published private(set) var history: ClimateHistory?
  @Published private(set) var isLoading = true
  @Published private(set) var isStale = true
  @Published private(set) var hasLoadError = false

  private let source: any HomeAssistantStateLoading
  private let loader: any ClimateHistoryLoading
  private let now: @Sendable () -> Date
  private let sleep: @Sendable (Duration) async throws -> Void
  private var observationID = UUID()
  private var requestID = UUID()
  private var stream: HomeAssistantBufferedUpdateStream<HomeAssistantStateUpdate>?
  private var loadTask: Task<Void, Never>?
  private var sampleTask: Task<Void, Never>?
  private var queuedFrame: ClimateHistory.Frame?
  private var pendingFrames: [ClimateHistory.Frame] = []
  private var latestFrame: ClimateHistory.Frame?
  private var sourceGeneration: UUID?
  private var duration: TimeInterval = 12 * 3600
  private var needsBackfill = true
  private var needsFullHistory = true
  private var sawSourceTransition = false
  private var hasLiveObservation = false

  init(
    source: any HomeAssistantStateLoading,
    loader: any ClimateHistoryLoading,
    now: @escaping @Sendable () -> Date = Date.init,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.source = source
    self.loader = loader
    self.now = now
    self.sleep = sleep
  }

  deinit {
    loadTask?.cancel()
    sampleTask?.cancel()
    stream?.cancel()
  }

  func observe(hours: Int) async {
    let nextDuration = Double(hours) * 3600
    needsFullHistory = needsFullHistory || history == nil || duration != nextDuration
    stop()
    sawSourceTransition = false
    hasLiveObservation = false
    let identifier = UUID()
    observationID = identifier
    if duration != nextDuration { history = history?.window(duration: nextDuration) }
    duration = nextDuration
    isLoading = true
    hasLoadError = false
    needsBackfill = true
    let updates = await source.stateUpdates()
    guard observationID == identifier, !Task.isCancelled else {
      updates.cancel()
      return
    }
    stream = updates
    defer {
      updates.cancel()
      if observationID == identifier { stop() }
    }
    do {
      for try await update in updates {
        try Task.checkCancellation()
        guard observationID == identifier else { return }
        receive(update)
      }
    } catch {
      if !Task.isCancelled, observationID == identifier { hasLoadError = true }
    }
  }

  func reset() {
    stop()
    history = nil
    sourceGeneration = nil
    hasLoadError = false
  }

  private func stop() {
    observationID = UUID()
    stream?.cancel()
    stream = nil
    cancelLoad()
    cancelSample()
    latestFrame = nil
    isStale = true
  }

  private func receive(_ update: HomeAssistantStateUpdate) {
    guard update.phase == .live else {
      cancelLoad()
      cancelSample()
      needsBackfill = true
      isStale = true
      if update.failure == .authentication || update.failure == .configuration
        || (sourceGeneration != nil && update.generation != sourceGeneration)
      {
        history = nil
        latestFrame = nil
        needsFullHistory = true
      }
      sawSourceTransition = true
      return
    }
    if !hasLiveObservation, !sawSourceTransition, let sourceGeneration,
      sourceGeneration != update.generation
    {
      history = nil
      latestFrame = nil
      needsFullHistory = true
    }
    sawSourceTransition = false
    let frame = ClimateHistory.Frame(timestamp: now(), states: update.states)
    if needsBackfill {
      needsBackfill = false
      reload(at: frame.timestamp)
    }
    sourceGeneration = update.generation
    hasLiveObservation = true
    record(frame)
    latestFrame = frame
  }

  private func reload(at end: Date) {
    cancelLoad()
    isLoading = true
    hasLoadError = false
    let identifier = UUID()
    requestID = identifier
    let retained =
      needsFullHistory
        || (history?.interval.end ?? .distantPast) <= end.addingTimeInterval(-duration)
      ? nil : history
    let start = max(end.addingTimeInterval(-duration), retained?.interval.end ?? .distantPast)
    let interval = DateInterval(start: min(start, end), end: end)
    loadTask = Task { [weak self, loader] in
      do {
        let loaded = try await loader.loadClimateHistory(interval: interval)
        try Task.checkCancellation()
        guard let self, requestID == identifier else { return }
        flushSample()
        var merged = loaded.mergingEarlierHistory(retained, duration: duration)
        for frame in pendingFrames where frame.timestamp >= loaded.interval.end {
          merged.append(frame, duration: duration)
        }
        history = merged
        pendingFrames = []
        isLoading = false
        isStale = false
        needsFullHistory = false
        loadTask = nil
      } catch {
        guard let self, requestID == identifier, !Task.isCancelled else { return }
        isLoading = false
        isStale = true
        hasLoadError = true
        pendingFrames = []
        loadTask = nil
      }
    }
  }

  private func cancelLoad() {
    requestID = UUID()
    loadTask?.cancel()
    loadTask = nil
    pendingFrames = []
    isLoading = false
  }

  private func record(_ frame: ClimateHistory.Frame) {
    let interval = max(duration / 600, 5)
    let lastTimestamp = pendingFrames.last?.timestamp ?? history?.frames.last?.timestamp
    let isSemanticChange = latestFrame.map { frame.hasSemanticChange(from: $0) } ?? true
    if isSemanticChange
      || lastTimestamp.map({ frame.timestamp.timeIntervalSince($0) >= interval }) ?? true
    {
      flushSample()
      publish(frame)
    } else {
      queuedFrame = frame
      guard sampleTask == nil else { return }
      let delay = max(
        interval - frame.timestamp.timeIntervalSince(lastTimestamp ?? frame.timestamp), 0)
      sampleTask = Task { [weak self, sleep] in
        do { try await sleep(.seconds(delay)) } catch { return }
        guard !Task.isCancelled else { return }
        self?.flushSample()
      }
    }
  }

  private func publish(_ frame: ClimateHistory.Frame) {
    if isLoading { pendingFrames.append(frame) }
    if !isLoading, !isStale, var current = history {
      current.append(frame, duration: duration)
      if current != history { history = current }
    }
  }

  private func flushSample() {
    let frame = queuedFrame
    cancelSample()
    if let frame { publish(frame) }
  }

  private func cancelSample() {
    sampleTask?.cancel()
    sampleTask = nil
    queuedFrame = nil
  }
}

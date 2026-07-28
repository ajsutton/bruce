import Foundation

@MainActor
final class HomeAssistantEVChargingLiveSubscription {
  enum Event {
    case progress
    case update(HomeAssistantEVChargingUpdate)
    case finished
    case failed(any Error)
  }

  struct Presentation {
    let mode: HomeAssistantEVChargingMode?
    let activity: HomeAssistantEVChargingActivity
    let isLive: Bool
    let isActivityLive: Bool
    let isRefreshing: Bool
    let problem: HomeAssistantEVChargingStore.Problem?
    let finishesProgress: Bool
  }

  struct ModeConfirmation {
    let mode: HomeAssistantEVChargingMode
    let isLive: Bool
    let isActivityLive: Bool
  }

  struct CurrentPresentation {
    let mode: HomeAssistantEVChargingMode?
    let activity: HomeAssistantEVChargingActivity
    let isLive: Bool
    let isActivityLive: Bool
  }

  private let client: any HomeAssistantEVCharging
  private let progressDelay: Duration
  private let sleep: @Sendable (Duration) async -> Void
  private(set) var revision = 0
  private(set) var isLive = false
  private var hasReceivedSnapshot = false
  private var receivedLiveActivityDuringModeChange = false
  private var liveModeDuringModeChange: HomeAssistantEVChargingMode?
  private var liveModeTimestampDuringModeChange: Date?
  private var modeTimestampAtChange: Date?
  private var latestModeTimestamp: Date?
  private var confirmedModeAwaitingLiveUpdate: HomeAssistantEVChargingMode?
  private var staleModeAwaitingLiveUpdate: HomeAssistantEVChargingMode?
  private var observationGeneration = UUID()

  init(
    client: any HomeAssistantEVCharging,
    progressDelay: Duration,
    sleep: @escaping @Sendable (Duration) async -> Void
  ) {
    self.client = client
    self.progressDelay = progressDelay
    self.sleep = sleep
  }

  func events() -> AsyncStream<Event> {
    AsyncStream { continuation in
      let progress = Task { [progressDelay, sleep] in
        await sleep(progressDelay)
        guard !Task.isCancelled else { return }
        continuation.yield(.progress)
      }
      let updates = Task { [client] in
        do {
          for try await update in client.evChargingUpdates() {
            try Task.checkCancellation()
            continuation.yield(.update(update))
          }
          continuation.yield(.finished)
        } catch is CancellationError {
          continuation.yield(.finished)
        } catch {
          continuation.yield(.failed(error))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in
        progress.cancel()
        updates.cancel()
      }
    }
  }

  func begin(preservingModeChangeSequence: Bool) -> UUID {
    observationGeneration = UUID()
    revision += 1
    isLive = false
    hasReceivedSnapshot = false
    if !preservingModeChangeSequence {
      clearModeSequence()
    }
    return observationGeneration
  }

  func invalidate() {
    observationGeneration = UUID()
    revision += 1
    isLive = false
    hasReceivedSnapshot = false
    clearModeSequence()
  }

  func beginModeChange() {
    receivedLiveActivityDuringModeChange = false
    liveModeDuringModeChange = nil
    liveModeTimestampDuringModeChange = nil
    modeTimestampAtChange = latestModeTimestamp
  }

  func confirmModeChange(
    _ confirmedMode: HomeAssistantEVChargingMode,
    previousMode: HomeAssistantEVChargingMode?,
    activity: HomeAssistantEVChargingActivity,
    wasLive: Bool
  ) -> ModeConfirmation {
    let receivedNewerLiveMode =
      liveModeDuringModeChange.map { liveMode in
        guard let liveTimestamp = liveModeTimestampDuringModeChange,
          let modeTimestampAtChange
        else {
          return liveMode != previousMode
        }
        return liveTimestamp > modeTimestampAtChange
      } ?? false
    let resolvedMode =
      receivedNewerLiveMode
      ? liveModeDuringModeChange ?? confirmedMode
      : confirmedMode
    let confirmedBeforeRequestCompleted =
      receivedNewerLiveMode || liveModeDuringModeChange == confirmedMode
    confirmedModeAwaitingLiveUpdate =
      confirmedBeforeRequestCompleted ? nil : confirmedMode
    staleModeAwaitingLiveUpdate =
      confirmedBeforeRequestCompleted ? nil : previousMode
    isLive = isLive || wasLive
    return ModeConfirmation(
      mode: resolvedMode,
      isLive: isLive,
      isActivityLive: isLive
        && receivedLiveActivityDuringModeChange
        && activity != .unavailable
    )
  }

  func presentation(
    for update: HomeAssistantEVChargingUpdate,
    current: CurrentPresentation,
    isChanging: Bool
  ) -> Presentation {
    revision += 1
    switch update {
    case .live(let snapshot):
      return livePresentation(
        snapshot,
        currentMode: current.mode,
        isChanging: isChanging
      )
    case .refreshing:
      isLive = false
      hasReceivedSnapshot = true
      return Presentation(
        mode: current.mode,
        activity: current.activity,
        isLive: false,
        isActivityLive: false,
        isRefreshing: true,
        problem: nil,
        finishesProgress: true
      )
    case .reconnecting(let snapshot):
      isLive = false
      hasReceivedSnapshot = true
      return stalePresentation(
        snapshot: snapshot,
        currentMode: current.mode,
        problem: .reconnecting,
        isChanging: isChanging
      )
    case .unavailable(let snapshot):
      isLive = false
      hasReceivedSnapshot = true
      return stalePresentation(
        snapshot: snapshot,
        currentMode: current.mode,
        currentActivity: current.activity,
        problem: .invalidResponse,
        isChanging: isChanging
      )
    }
  }

  func finish() {
    observationGeneration = UUID()
    revision += 1
    isLive = false
    clearModeSequence()
  }
}

extension HomeAssistantEVChargingLiveSubscription {
  private func livePresentation(
    _ snapshot: HomeAssistantEVChargingSnapshot,
    currentMode: HomeAssistantEVChargingMode?,
    isChanging: Bool
  ) -> Presentation {
    isLive = true
    hasReceivedSnapshot = true
    let nextMode = liveMode(
      snapshot.mode,
      timestamp: snapshot.modeLastUpdated,
      currentMode: currentMode,
      isChanging: isChanging
    )
    return Presentation(
      mode: nextMode,
      activity: snapshot.activity,
      isLive: true,
      isActivityLive: snapshot.activity != .unavailable,
      isRefreshing: false,
      problem: nil,
      finishesProgress: !isChanging
    )
  }

  private func liveMode(
    _ liveMode: HomeAssistantEVChargingMode,
    timestamp: Date?,
    currentMode: HomeAssistantEVChargingMode?,
    isChanging: Bool
  ) -> HomeAssistantEVChargingMode? {
    if !isChanging, let latestModeTimestamp {
      guard let timestamp, timestamp >= latestModeTimestamp else {
        return currentMode
      }
    }
    if let timestamp {
      latestModeTimestamp = max(latestModeTimestamp ?? timestamp, timestamp)
    }
    if isChanging {
      receivedLiveActivityDuringModeChange = true
      if shouldRetainModeChangeUpdate(timestamp: timestamp) {
        liveModeDuringModeChange = liveMode
        liveModeTimestampDuringModeChange = timestamp
      }
      return currentMode
    }
    if liveMode == confirmedModeAwaitingLiveUpdate {
      clearAwaitingConfirmation()
      return liveMode
    }
    if liveMode == staleModeAwaitingLiveUpdate,
      !isNewerThanModeAtChange(timestamp)
    {
      return currentMode
    }
    if confirmedModeAwaitingLiveUpdate != nil {
      clearAwaitingConfirmation()
    }
    return liveMode
  }

  private func stalePresentation(
    snapshot: HomeAssistantEVChargingSnapshot?,
    currentMode: HomeAssistantEVChargingMode?,
    currentActivity: HomeAssistantEVChargingActivity? = nil,
    problem: HomeAssistantEVChargingStore.Problem,
    isChanging: Bool
  ) -> Presentation {
    let canReplaceMode = !isChanging && confirmedModeAwaitingLiveUpdate == nil
    return Presentation(
      mode: canReplaceMode ? snapshot?.mode ?? currentMode : currentMode,
      activity: snapshot?.activity ?? currentActivity ?? .unavailable,
      isLive: false,
      isActivityLive: false,
      isRefreshing: false,
      problem: problem,
      finishesProgress: !isChanging
    )
  }

  private func isNewerThanModeAtChange(_ timestamp: Date?) -> Bool {
    guard let timestamp, let modeTimestampAtChange else { return false }
    return timestamp > modeTimestampAtChange
  }

  private func shouldRetainModeChangeUpdate(timestamp: Date?) -> Bool {
    guard let retainedTimestamp = liveModeTimestampDuringModeChange else {
      return liveModeDuringModeChange == nil || timestamp != nil
    }
    guard let timestamp else { return false }
    return timestamp >= retainedTimestamp
  }
}

extension HomeAssistantEVChargingLiveSubscription {
  private func clearAwaitingConfirmation() {
    confirmedModeAwaitingLiveUpdate = nil
    staleModeAwaitingLiveUpdate = nil
  }

  private func clearModeSequence() {
    clearAwaitingConfirmation()
    receivedLiveActivityDuringModeChange = false
    liveModeDuringModeChange = nil
    liveModeTimestampDuringModeChange = nil
    modeTimestampAtChange = nil
    latestModeTimestamp = nil
  }

  func isCurrent(_ generation: UUID) -> Bool {
    observationGeneration == generation
  }

  var shouldShowProgress: Bool {
    !hasReceivedSnapshot
  }

  var loadedSnapshotIsLive: Bool {
    !client.providesContinuousUpdates || isLive
  }

  var expectsContinuousUpdates: Bool {
    client.providesContinuousUpdates
  }

  var latestLiveModeTimestamp: Date? {
    latestModeTimestamp
  }

  func recordReconciledMode(timestamp: Date?) {
    guard let timestamp else { return }
    latestModeTimestamp = max(latestModeTimestamp ?? timestamp, timestamp)
  }
}

import Foundation

@MainActor
final class HomeAssistantEVChargingLiveSubscription {
  private let client: any HomeAssistantEVCharging
  private let progressDelay: Duration
  private let sleep: @Sendable (Duration) async -> Void
  private(set) var revision = 0, isLive = false
  private(set) var hasCompletedDiscovery: Bool
  private var hasReceivedSnapshot = false, receivedLiveActivityDuringModeChange = false
  private var liveModeDuringModeChange: HomeAssistantEVChargingMode?
  private var liveDecisionDuringModeChange: HomeAssistantEVChargingDecision?
  private var liveActivityDuringModeChange: HomeAssistantEVChargingActivity?
  private var liveModeTimestampDuringModeChange: Date?
  private var modeTimestampAtChange: Date?
  private var latestModeTimestamp: Date?
  private var confirmedModeAwaitingLiveUpdate: HomeAssistantEVChargingMode?
  private var staleModeAwaitingLiveUpdate: HomeAssistantEVChargingMode?
  private var observationGeneration = UUID()

  init(
    client: any HomeAssistantEVCharging,
    progressDelay: Duration,
    hasCompletedDiscovery: Bool,
    sleep: @escaping @Sendable (Duration) async -> Void
  ) {
    self.client = client
    self.progressDelay = progressDelay
    self.hasCompletedDiscovery = hasCompletedDiscovery
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
    hasCompletedDiscovery = false
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
    hasCompletedDiscovery = false
    clearModeSequence()
  }

  func beginModeChange() {
    receivedLiveActivityDuringModeChange = false
    liveModeDuringModeChange = nil
    liveDecisionDuringModeChange = nil
    liveActivityDuringModeChange = nil
    liveModeTimestampDuringModeChange = nil
    modeTimestampAtChange = latestModeTimestamp
  }

  func confirmModeChange(
    _ confirmedMode: HomeAssistantEVChargingMode,
    previousMode: HomeAssistantEVChargingMode?,
    activity: HomeAssistantEVChargingActivity,
    decision: HomeAssistantEVChargingDecision,
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
    let matchingLiveModeConfirmed =
      liveModeDuringModeChange == confirmedMode
      && (liveModeTimestampDuringModeChange == nil
        || modeTimestampAtChange == nil
        || isNewerThanModeAtChange(liveModeTimestampDuringModeChange))
    let confirmedBeforeRequestCompleted =
      receivedNewerLiveMode || matchingLiveModeConfirmed
    confirmedModeAwaitingLiveUpdate =
      confirmedBeforeRequestCompleted ? nil : confirmedMode
    staleModeAwaitingLiveUpdate =
      confirmedBeforeRequestCompleted ? nil : previousMode
    isLive = isLive || wasLive
    return ModeConfirmation(
      mode: resolvedMode,
      decision: confirmedBeforeRequestCompleted
        ? liveDecisionDuringModeChange ?? decision
        : decision,
      isLive: isLive,
      isActivityLive: isLive
        && receivedLiveActivityDuringModeChange
        && activity != .unavailable,
      isDecisionLive: isLive && confirmedBeforeRequestCompleted
    )
  }

  func presentation(
    for update: HomeAssistantEVChargingUpdate,
    current: CurrentPresentation,
    isChanging: Bool
  ) -> Presentation {
    revision += 1
    switch update {
    case .absent:
      return absentPresentation(isChanging: isChanging)
    case .live(let snapshot):
      return livePresentation(
        snapshot,
        current: current,
        isChanging: isChanging
      )
    case .refreshing:
      isLive = false
      hasReceivedSnapshot = true
      return Presentation(
        mode: current.mode,
        activity: current.activity,
        decision: current.decision,
        isLive: false,
        isActivityLive: false,
        isDecisionLive: false,
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
        currentDecision: current.decision,
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
        currentDecision: current.decision,
        problem: .invalidResponse,
        isChanging: isChanging
      )
    }
  }

  private func absentPresentation(isChanging: Bool) -> Presentation {
    isLive = false
    hasReceivedSnapshot = true
    hasCompletedDiscovery = true
    clearModeSequence()
    return Presentation(
      mode: nil,
      activity: .unavailable,
      decision: .unavailable,
      isLive: false,
      isActivityLive: false,
      isDecisionLive: false,
      isRefreshing: false,
      problem: nil,
      finishesProgress: true
    )
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
    current: CurrentPresentation,
    isChanging: Bool
  ) -> Presentation {
    isLive = true
    hasReceivedSnapshot = true
    hasCompletedDiscovery = true
    let resolution = liveMode(
      snapshot,
      currentMode: current.mode,
      isChanging: isChanging
    )
    return Presentation(
      mode: resolution.mode,
      activity: resolution.accepted
        ? (isChanging ? liveActivityDuringModeChange ?? snapshot.activity : snapshot.activity)
        : current.activity,
      decision: resolution.accepted
        ? (isChanging ? liveDecisionDuringModeChange ?? snapshot.decision : snapshot.decision)
        : current.decision,
      isLive: true,
      isActivityLive: resolution.accepted
        ? snapshot.activity != .unavailable : current.isActivityLive,
      isDecisionLive: resolution.accepted ? !isChanging : current.isDecisionLive,
      isRefreshing: false,
      problem: nil,
      finishesProgress: !isChanging
    )
  }

  private func liveMode(
    _ snapshot: HomeAssistantEVChargingSnapshot,
    currentMode: HomeAssistantEVChargingMode?,
    isChanging: Bool
  ) -> (mode: HomeAssistantEVChargingMode?, accepted: Bool) {
    let liveMode = snapshot.mode
    let timestamp = snapshot.modeLastUpdated
    if !isChanging, let latestModeTimestamp {
      guard let timestamp, timestamp >= latestModeTimestamp else {
        return (currentMode, false)
      }
    }
    if let timestamp {
      latestModeTimestamp = max(latestModeTimestamp ?? timestamp, timestamp)
    }
    if isChanging {
      let accepted = shouldRetainModeChangeUpdate(timestamp: timestamp)
      if accepted {
        receivedLiveActivityDuringModeChange = true
        liveModeDuringModeChange = liveMode
        liveActivityDuringModeChange = snapshot.activity
        liveDecisionDuringModeChange = snapshot.decision
        liveModeTimestampDuringModeChange = timestamp
      }
      return (currentMode, accepted)
    }
    if liveMode == confirmedModeAwaitingLiveUpdate {
      clearAwaitingConfirmation()
      return (liveMode, true)
    }
    if liveMode == staleModeAwaitingLiveUpdate,
      !isNewerThanModeAtChange(timestamp)
    {
      return (currentMode, false)
    }
    if confirmedModeAwaitingLiveUpdate != nil {
      clearAwaitingConfirmation()
    }
    return (liveMode, true)
  }

  private func stalePresentation(
    snapshot: HomeAssistantEVChargingSnapshot?,
    currentMode: HomeAssistantEVChargingMode?,
    currentActivity: HomeAssistantEVChargingActivity? = nil,
    currentDecision: HomeAssistantEVChargingDecision,
    problem: HomeAssistantEVChargingStore.Problem,
    isChanging: Bool
  ) -> Presentation {
    let canReplaceMode = !isChanging && confirmedModeAwaitingLiveUpdate == nil
    return Presentation(
      mode: canReplaceMode ? snapshot?.mode ?? currentMode : currentMode,
      activity: snapshot?.activity ?? currentActivity ?? .unavailable,
      decision: snapshot?.decision ?? currentDecision,
      isLive: false,
      isActivityLive: false,
      isDecisionLive: false,
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
    if timestamp != nil, modeTimestampAtChange != nil,
      !isNewerThanModeAtChange(timestamp)
    {
      return false
    }
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
    liveDecisionDuringModeChange = nil
    liveActivityDuringModeChange = nil
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

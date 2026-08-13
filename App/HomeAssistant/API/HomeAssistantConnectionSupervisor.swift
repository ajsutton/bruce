import Foundation

actor HomeAssistantConnectionSupervisor: HomeAssistantStateLoading {
  let session: HomeAssistantSession
  let apiClient: HomeAssistantAPIClient
  let connector: any HomeAssistantWebSocketConnecting
  let credentialEvents: HomeAssistantCredentialEvents
  let retryPolicy: HomeAssistantConnectionRetryPolicy
  let clock: HomeAssistantConnectionClock
  let heartbeatIdleInterval: Duration
  let heartbeatResponseDeadline: Duration
  let stableConnectionInterval: Duration
  let phaseDeadline: Duration
  let connectionSnapshot: @Sendable () async -> HomeAssistantCredentialSnapshot

  var state = HomeAssistantConnectionState.stopped
  var credentialSnapshot: HomeAssistantCredentialSnapshot?
  var continuations: [UUID: Continuation] = [:]
  var readinessWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
  var credentialTask: Task<Void, Never>?
  var lifecycleTask: Task<Void, Never>?
  var runningLifecycleID: UUID?
  var publicationLifecycleID: UUID?
  var currentConnection: (any HomeAssistantWebSocketConnection)?
  var currentAttempt: HomeAssistantConnectionAttempt?
  var currentAccess: HomeAssistantWebSocketAccess?
  var stableConnectionTask: Task<Void, Never>?
  var stabilityEpoch = UUID(), shutdownGeneration = UUID()
  var isApplicationActive = true
  var shouldRestartAfterLifecycleEnds = false
  var failureCount = 0
  var lastFailedURL: URL?
  var terminallyFailedURLs: Set<URL> = []
  var latestUpdate: Update?
  var latestSnapshot = HomeAssistantStateReconciler.Snapshot()
  var registryGeneration = UUID()
  var liveSequence = 0
  var hasReachedLiveForAuthenticationSession = false
  var refreshedCredentialGeneration: Int?
  var requiresUserAction = false
  var terminalError: (any Error)?
  var phaseStartedAt: TimeInterval
  var lastSuccessfulEventAt: TimeInterval?
  var acceleratedReplacementPending = false
  var pendingReplacementTrigger: HomeAssistantConnectionTrigger?
  var activeCommandCount = 0
  var isExplicitlyStopped = false
  var disconnectPreparationID: UUID?

  init(
    session: HomeAssistantSession,
    apiClient: HomeAssistantAPIClient? = nil,
    connector: any HomeAssistantWebSocketConnecting,
    credentialEvents: HomeAssistantCredentialEvents,
    retryPolicy: HomeAssistantConnectionRetryPolicy = HomeAssistantConnectionRetryPolicy(),
    clock: HomeAssistantConnectionClock = HomeAssistantConnectionClock(),
    heartbeatIdleInterval: Duration = .seconds(60),
    heartbeatResponseDeadline: Duration = .seconds(30),
    stableConnectionInterval: Duration = .seconds(120),
    phaseDeadline: Duration = .seconds(30),
    connectionSnapshot: (@Sendable () async -> HomeAssistantCredentialSnapshot)? = nil
  ) {
    self.session = session
    self.apiClient = apiClient ?? HomeAssistantAPIClient(session: session)
    self.connector = connector
    self.credentialEvents = credentialEvents
    self.retryPolicy = retryPolicy
    self.clock = clock
    self.heartbeatIdleInterval = heartbeatIdleInterval
    self.heartbeatResponseDeadline = heartbeatResponseDeadline
    self.stableConnectionInterval = stableConnectionInterval
    self.phaseDeadline = phaseDeadline
    self.connectionSnapshot = connectionSnapshot ?? { await session.connectionSnapshot() }
    phaseStartedAt = clock.now()
  }

  func stateUpdates() -> Stream {
    Stream { continuation in
      let id = UUID()
      self.addConsumer(id: id, continuation: continuation)
      continuation.onTermination = { [weak supervisor = self] _ in
        Task { await supervisor?.removeConsumer(id: id) }
      }
    }
  }

  func requireFreshLiveData() async throws {
    guard disconnectPreparationID == nil else { throw HomeAssistantAPIError.noCredentials }
    isExplicitlyStopped = false
    let generation = shutdownGeneration
    let snapshot = await connectionSnapshot()
    guard shutdownGeneration == generation, !isExplicitlyStopped else {
      throw CancellationError()
    }
    receiveCredentialSnapshot(snapshot)
    guard credentialSnapshot?.availability != .missing else {
      throw HomeAssistantAPIError.noCredentials
    }
    guard !requiresUserAction else {
      throw terminalError ?? HomeAssistantAPIError.unauthorized
    }
    let id = UUID()
    let shouldRequestReplacement = readinessWaiters.isEmpty
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        readinessWaiters[id] = continuation
        startCredentialObservationIfNeeded()
        if shouldRequestReplacement {
          switch state {
          case .connecting, .authenticating, .synchronizing:
            break
          case .live, .backingOff, .waitingForConnectivity:
            requestReplacement(trigger: .manualRequest)
          case .stopped, .waitingForCredentials, .suspended, .requiresUserAction:
            reconcileLifecycle(trigger: .manualRequest)
          }
        }
      }
    } onCancel: {
      Task { await self.cancelReadinessWaiter(id: id) }
    }
  }

  func setApplicationActive(_ isActive: Bool) {
    guard isApplicationActive != isActive else { return }
    isApplicationActive = isActive
    if isActive {
      requestReplacement(trigger: .appActivity)
    } else {
      publishReconnecting()
      stopCurrentLifecycle(restartWhenRunnable: false)
      transition(to: .suspended, trigger: .appActivity)
    }
  }

  func stop() async {
    disconnectPreparationID = nil
    isExplicitlyStopped = true
    shutdownGeneration = UUID()
    let lifecycleTask = lifecycleTask
    let credentialTask = credentialTask
    continuations.values.forEach { $0.finish() }
    continuations = [:]
    failReadinessWaiters(with: CancellationError())
    stopCurrentLifecycle(restartWhenRunnable: false)
    credentialTask?.cancel()
    self.credentialTask = nil
    credentialSnapshot = nil
    latestUpdate = nil
    latestSnapshot = .init()
    registryGeneration = UUID()
    requiresUserAction = false
    terminalError = nil
    refreshedCredentialGeneration = nil
    transition(to: .stopped, trigger: .consumerIntent)
    await lifecycleTask?.value
    await credentialTask?.value
  }

  func receiveCredentialSnapshot(_ snapshot: HomeAssistantCredentialSnapshot) {
    let previous = credentialSnapshot
    if let previous,
      snapshot.authenticationSessionEpoch < previous.authenticationSessionEpoch
        || (snapshot.authenticationSessionEpoch == previous.authenticationSessionEpoch
          && snapshot.persistenceGeneration < previous.persistenceGeneration)
    {
      return
    }
    credentialSnapshot = snapshot
    let authenticationChanged =
      previous?.authenticationSessionEpoch != snapshot.authenticationSessionEpoch
    if authenticationChanged {
      if previous != nil {
        publishAuthenticationReplacement()
      }
      latestSnapshot = .init()
      registryGeneration = UUID()
      failureCount = 0
      lastFailedURL = nil
      terminallyFailedURLs = []
      hasReachedLiveForAuthenticationSession = false
      refreshedCredentialGeneration = nil
      requiresUserAction = false
      terminalError = nil
      requestReplacement(trigger: .credentials)
    } else {
      reconcileLifecycle(trigger: .credentials)
    }
  }

  func reconcileLifecycle(trigger: HomeAssistantConnectionTrigger) {
    guard !isExplicitlyStopped else {
      transition(to: .stopped, trigger: trigger)
      return
    }
    guard hasConsumerIntent else {
      stopCurrentLifecycle(restartWhenRunnable: false)
      credentialTask?.cancel()
      self.credentialTask = nil
      latestUpdate = nil
      latestSnapshot = .init()
      transition(to: .stopped, trigger: trigger)
      return
    }
    guard let credentialSnapshot else {
      transition(to: .waitingForCredentials, trigger: trigger)
      return
    }
    switch credentialSnapshot.availability {
    case .missing:
      stopCurrentLifecycle(restartWhenRunnable: false)
      transition(to: .waitingForCredentials, trigger: trigger)
      failReadinessWaiters(with: HomeAssistantAPIError.noCredentials)
    case .rejected:
      stopCurrentLifecycle(restartWhenRunnable: false)
      requiresUserAction = true
      terminalError = HomeAssistantAPIError.reauthenticationRequired
      publishUnavailable(error: HomeAssistantAPIError.reauthenticationRequired)
      transition(
        to: .requiresUserAction,
        trigger: trigger,
        error: HomeAssistantAPIError.reauthenticationRequired
      )
      failReadinessWaiters(with: HomeAssistantAPIError.reauthenticationRequired)
    case .ready:
      guard isApplicationActive else {
        stopCurrentLifecycle(restartWhenRunnable: false)
        transition(to: .suspended, trigger: trigger)
        return
      }
      startLifecycleIfNeeded(trigger: trigger)
    }
  }

  func requestReplacement(trigger: HomeAssistantConnectionTrigger) {
    guard hasConsumerIntent else {
      reconcileLifecycle(trigger: trigger)
      return
    }
    if state == .live, trigger != .credentials {
      if trigger == .manualRequest {
        publishRefreshing()
      } else {
        publishReconnecting()
      }
    }
    invalidateStabilityTimer()
    shouldRestartAfterLifecycleEnds = true
    if lifecycleTask != nil {
      pendingReplacementTrigger = trigger
      let replacedAttempt = currentAttempt
      publicationLifecycleID = nil
      currentAttempt = nil
      currentConnection?.cancel()
      if let replacedAttempt {
        Task { await replacedAttempt.finish() }
      }
      lifecycleTask?.cancel()
    } else {
      reconcileLifecycle(trigger: trigger)
    }
  }

}

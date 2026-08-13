import Foundation

extension HomeAssistantConnectionSupervisor {
  func recover(
    from error: any Error,
    lifecycleID: UUID,
    trigger: HomeAssistantConnectionTrigger
  ) async -> Bool {
    guard isRunnable, runningLifecycleID == lifecycleID, !Task.isCancelled else {
      return false
    }
    let attemptID = currentAttempt?.id
    let accessGeneration = currentAccess?.credentialGeneration
    let canTryAlternate = await canTryAlternateRoute(after: error)
    guard
      isRunnable,
      runningLifecycleID == lifecycleID,
      publicationLifecycleID == lifecycleID,
      currentAttempt?.id == attemptID,
      currentAccess?.credentialGeneration == accessGeneration,
      !Task.isCancelled
    else {
      return false
    }
    if isTerminal(error), let failedURL = currentAccess?.baseURL {
      terminallyFailedURLs.insert(failedURL)
    }
    if isTerminal(error), !canTryAlternate {
      enterTerminalState(error, trigger: trigger)
      return false
    }
    if let failedURL = currentAccess?.baseURL,
      !preservesPreferredRoute(after: error) || canTryAlternate
    {
      lastFailedURL = failedURL
    }
    failureCount += 1
    publishReconnecting()
    failReadinessWaiters(with: error)
    let nextState: HomeAssistantConnectionState =
      HomeAssistantRequestRouter.isConnectivityFailure(error)
      ? .waitingForConnectivity : .backingOff
    let delay = retryPolicy.delay(afterFailure: failureCount)
    transition(
      to: nextState,
      trigger: trigger,
      error: error,
      retryDelay: delay
    )
    do {
      try await clock.sleep(delay, .milliseconds(500))
      try Task.checkCancellation()
      return runningLifecycleID == lifecycleID && isRunnable
    } catch {
      return false
    }
  }

  private func enterTerminalState(
    _ error: any Error,
    trigger: HomeAssistantConnectionTrigger
  ) {
    requiresUserAction = true
    terminalError = error
    publishUnavailable(error: error)
    transition(to: .requiresUserAction, trigger: trigger, error: error)
    failReadinessWaiters(with: error)
  }

  func refreshAfterAuthenticationRejection(lifecycleID: UUID) async -> Bool {
    guard runningLifecycleID == lifecycleID, let access = currentAccess else {
      return false
    }
    let attemptID = currentAttempt?.id
    if refreshedCredentialGeneration == access.credentialGeneration {
      return await rejectPreviouslyRefreshedAccess(
        access,
        lifecycleID: lifecycleID,
        attemptID: attemptID
      )
    }
    return await refreshRejectedAccess(
      access,
      lifecycleID: lifecycleID,
      attemptID: attemptID
    )
  }

  private func rejectPreviouslyRefreshedAccess(
    _ access: HomeAssistantWebSocketAccess,
    lifecycleID: UUID,
    attemptID: UUID?
  ) async -> Bool {
    if await canTryAlternateRoute(after: HomeAssistantAPIError.unauthorized) {
      guard isCurrentAuthenticationRecovery(lifecycleID, access, attemptID) else {
        return false
      }
      terminallyFailedURLs.insert(access.baseURL)
      lastFailedURL = access.baseURL
      failureCount += 1
      publishReconnecting()
      transition(to: .backingOff, trigger: .authentication)
      return true
    }
    guard isCurrentAuthenticationRecovery(lifecycleID, access, attemptID) else {
      return false
    }
    do {
      try await session.rejectWebSocketAccess(access)
    } catch HomeAssistantAPIError.reauthenticationRequired {
    } catch {
      guard isCurrentAuthenticationRecovery(lifecycleID, access, attemptID) else {
        return false
      }
      return await recover(from: error, lifecycleID: lifecycleID, trigger: .authentication)
    }
    guard isCurrentAuthenticationRecovery(lifecycleID, access, attemptID) else {
      return false
    }
    enterAuthenticationTerminalState(HomeAssistantAPIError.unauthorized)
    return false
  }

  private func refreshRejectedAccess(
    _ access: HomeAssistantWebSocketAccess,
    lifecycleID: UUID,
    attemptID: UUID?
  ) async -> Bool {
    do {
      try await session.refreshRejectedWebSocketAccess(access)
      guard isCurrentAuthenticationRecovery(lifecycleID, access, attemptID) else { return false }
      let refreshedAccess = try await session.authenticatedWebSocketAccess()
      guard isCurrentAuthenticationRecovery(lifecycleID, access, attemptID) else { return false }
      refreshedCredentialGeneration = refreshedAccess.credentialGeneration
      return true
    } catch is CancellationError {
      return false
    } catch HomeAssistantAPIError.reauthenticationRequired {
      guard isCurrentAuthenticationRecovery(lifecycleID, access, attemptID) else { return false }
      enterAuthenticationTerminalState(HomeAssistantAPIError.reauthenticationRequired)
      return false
    } catch {
      return await recover(from: error, lifecycleID: lifecycleID, trigger: .authentication)
    }
  }

  private func enterAuthenticationTerminalState(_ error: HomeAssistantAPIError) {
    requiresUserAction = true
    terminalError = error
    publishUnavailable(error: error)
    transition(to: .requiresUserAction, trigger: .authentication, error: error)
    failReadinessWaiters(with: error)
  }

  private func isCurrentAuthenticationRecovery(
    _ lifecycleID: UUID,
    _ access: HomeAssistantWebSocketAccess,
    _ attemptID: UUID?
  ) -> Bool {
    isRunnable
      && runningLifecycleID == lifecycleID
      && publicationLifecycleID == lifecycleID
      && currentAttempt?.id == attemptID
      && currentAccess?.authenticationSessionEpoch == access.authenticationSessionEpoch
      && currentAccess?.credentialGeneration == access.credentialGeneration
      && credentialSnapshot?.authenticationSessionEpoch == access.authenticationSessionEpoch
      && !Task.isCancelled
  }

  func publishReconnecting() {
    guard let latestUpdate else {
      let update = Update.reconnecting([], generation: UUID())
      self.latestUpdate = update
      continuations.values.forEach { $0.yield(update) }
      return
    }
    let update = Update.reconnecting(
      latestUpdate.states,
      generation: latestUpdate.generation
    )
    self.latestUpdate = update
    continuations.values.forEach { $0.yield(update) }
  }

  func publishRefreshing() {
    guard let latestUpdate else { return }
    let update = Update.refreshing(
      latestUpdate.states,
      generation: latestUpdate.generation
    )
    self.latestUpdate = update
    continuations.values.forEach { $0.yield(update) }
  }

  func publishAuthenticationReplacement() {
    let update = Update.reconnecting([], generation: UUID())
    latestUpdate = update
    continuations.values.forEach { $0.yield(update) }
  }

  func publishUnavailable(error: any Error) {
    let update = Update.unavailable(
      latestUpdate?.states ?? [],
      generation: latestUpdate?.generation ?? UUID(),
      failure: Self.presentationFailure(for: error)
    )
    latestUpdate = update
    continuations.values.forEach { $0.yield(update) }
  }

  private static func presentationFailure(for error: any Error) -> Update.Failure {
    if let apiError = error as? HomeAssistantAPIError {
      return switch apiError {
      case .noCredentials, .unauthorized, .reauthenticationRequired: .authentication
      case .invalidServerURL, .incompatibleServer: .configuration
      case .invalidResponse, .server, .staleOperation: .unknown
      }
    }
    return .unknown
  }

  func invalidateStabilityTimer() {
    stabilityEpoch = UUID()
    stableConnectionTask?.cancel()
    stableConnectionTask = nil
  }

  func startStabilityTimer(lifecycleID: UUID, attemptID: UUID) {
    invalidateStabilityTimer()
    let epoch = stabilityEpoch
    stableConnectionTask = Task {
      do {
        try await clock.sleep(
          stableConnectionInterval,
          stableConnectionInterval.scaled(by: 0.1)
        )
        guard
          runningLifecycleID == lifecycleID,
          currentAttempt?.id == attemptID,
          stabilityEpoch == epoch,
          state == .live
        else { return }
        failureCount = 0
      } catch {
        return
      }
    }
  }

  func resolveReadinessWaiters() {
    guard !readinessWaiters.isEmpty else { return }
    let waiters = readinessWaiters.values
    readinessWaiters = [:]
    waiters.forEach { $0.resume() }
    scheduleIntentReconciliation()
  }

  func failReadinessWaiters(with error: any Error) {
    guard !readinessWaiters.isEmpty else { return }
    let waiters = readinessWaiters.values
    readinessWaiters = [:]
    waiters.forEach { $0.resume(throwing: error) }
    scheduleIntentReconciliation()
  }

  private func scheduleIntentReconciliation() {
    let generation = shutdownGeneration
    Task {
      guard shutdownGeneration == generation, !isExplicitlyStopped else { return }
      reconcileLifecycle(trigger: .consumerIntent)
    }
  }

  func isTerminal(_ error: any Error) -> Bool {
    if let urlError = error as? URLError {
      return Self.isTerminal(urlError)
    }
    if error is HomeAssistantCredentialStoreError {
      return false
    }
    if let authenticationError = error as? HomeAssistantAuthenticationError {
      return isTerminal(authenticationError)
    }
    guard let apiError = error as? HomeAssistantAPIError else { return false }
    switch apiError {
    case .invalidResponse:
      return !hasReachedLiveForAuthenticationSession
    case .noCredentials, .invalidServerURL, .unauthorized, .reauthenticationRequired,
      .incompatibleServer:
      return true
    case .server(let statusCode):
      return statusCode != 429 && statusCode < 500
    case .staleOperation:
      return false
    }
  }

  private static func isTerminal(_ error: URLError) -> Bool {
    switch error.code {
    case .serverCertificateHasBadDate, .serverCertificateUntrusted,
      .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
      .clientCertificateRejected, .clientCertificateRequired:
      true
    default:
      false
    }
  }

  private func isTerminal(_ error: HomeAssistantAuthenticationError) -> Bool {
    if case .serverRejectedRequest(let statusCode, _) = error {
      return statusCode != 429 && statusCode < 500
    }
    return !hasReachedLiveForAuthenticationSession
  }

  private func preservesPreferredRoute(after error: any Error) -> Bool {
    if case HomeAssistantAPIError.staleOperation = error { return true }
    return false
  }

  private func canTryAlternateRoute(after error: any Error) async -> Bool {
    guard isTerminal(error), let failedURL = currentAccess?.baseURL else { return false }
    guard let accesses = try? await session.currentWebSocketAccesses() else { return false }
    return accesses.contains {
      $0.baseURL != failedURL && !terminallyFailedURLs.contains($0.baseURL)
    }
  }
}

extension Duration {
  fileprivate func scaled(by scale: Double) -> Duration {
    let components = self.components
    let seconds =
      Double(components.seconds)
      + Double(components.attoseconds) / 1_000_000_000_000_000_000
    return .nanoseconds(Int64(seconds * scale * 1_000_000_000))
  }
}

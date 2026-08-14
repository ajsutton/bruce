import Foundation

private struct HomeAssistantCredentialRejectionContext {
  let credentials: HomeAssistantCredentials
  let generation: Int
  let operationEpoch: Int
}

extension HomeAssistantSession {
  func rejectCredentials(generation: Int) async throws -> Never {
    if credentials == nil, rejectedCredentialGeneration == generation {
      throw HomeAssistantAPIError.reauthenticationRequired
    }
    try prepareCredentialRejection(generation: generation)
    let waiterID = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        addCredentialRejectionWaiter(
          id: waiterID,
          generation: generation,
          continuation: continuation
        )
        if Task.isCancelled {
          cancelCredentialRejectionWaiter(id: waiterID)
        }
      }
    } onCancel: {
      Task {
        await self.cancelCredentialRejectionWaiter(id: waiterID)
      }
    }
    try Task.checkCancellation()
    throw HomeAssistantAPIError.reauthenticationRequired
  }

  private func addCredentialRejectionWaiter(
    id waiterID: UUID,
    generation: Int,
    continuation: CredentialRejectionWaiter
  ) {
    guard var activeAttempt = credentialRejectionAttempt,
      activeAttempt.generation == generation
    else {
      continuation.resume(throwing: HomeAssistantAPIError.staleOperation)
      return
    }
    activeAttempt.waiters[waiterID] = continuation
    credentialRejectionAttempt = activeAttempt
    rejectionWaiterRegistered(activeAttempt.waiters.count)
  }

  private func prepareCredentialRejection(generation: Int) throws {
    if let activeAttempt = credentialRejectionAttempt {
      guard activeAttempt.generation == generation else {
        throw HomeAssistantAPIError.staleOperation
      }
      return
    }
    startCredentialRejection(context: try beginCredentialRejection(generation: generation))
  }

  private func beginCredentialRejection(
    generation: Int
  ) throws -> HomeAssistantCredentialRejectionContext {
    guard credentialGeneration == generation, let rejectedCredentials = credentials else {
      throw HomeAssistantAPIError.staleOperation
    }
    guard pendingReplacementOperationEpoch == nil else {
      throw HomeAssistantAPIError.staleOperation
    }
    authenticationOperationEpoch += 1
    let operationEpoch = authenticationOperationEpoch
    pendingReplacementOperationEpoch = operationEpoch
    rejectedCredentialGeneration = generation
    authenticationSessionEpoch += 1
    return HomeAssistantCredentialRejectionContext(
      credentials: rejectedCredentials,
      generation: generation,
      operationEpoch: operationEpoch
    )
  }

  private func startCredentialRejection(
    context: HomeAssistantCredentialRejectionContext
  ) {
    let attemptID = UUID()
    credentialRejectionAttempt = CredentialRejectionAttempt(
      id: attemptID,
      generation: context.generation,
      operationEpoch: context.operationEpoch,
      task: nil,
      waiters: [:]
    )
    let task = Task {
      let result: Result<Void, any Error>
      do {
        try await performCredentialRejection(context)
        result = .success(())
      } catch {
        result = .failure(error)
      }
      completeCredentialRejection(attemptID: attemptID, with: result)
    }
    credentialRejectionAttempt?.task = task
  }

  private func performCredentialRejection(
    _ context: HomeAssistantCredentialRejectionContext
  ) async throws {
    await publishCredentialSnapshot()
    try await withHomeAssistantPersistence(gate: persistenceGate) {
      guard try await credentialStore.replace(nil, ifCurrentIs: context.credentials) else {
        return try await reconcileRejectedCredentials(context)
      }
      try await checkPersistenceCancellation(
        restoring: context.credentials,
        replacing: nil,
        generation: context.generation
      )
      guard credentialGeneration == context.generation, credentials == context.credentials else {
        _ = try await HomeAssistantCredentialRecovery.repair(
          credentials,
          replacing: nil,
          in: credentialStore
        )
        throw HomeAssistantAPIError.staleOperation
      }
      credentials = nil
      credentialGeneration += 1
      successfulRouteSourceGeneration = nil
      await publishCredentialSnapshot()
    }
  }

  private func reconcileRejectedCredentials(
    _ context: HomeAssistantCredentialRejectionContext
  ) async throws {
    let persistedCredentials = try await credentialStore.load()
    guard credentialGeneration == context.generation, credentials == context.credentials else {
      throw HomeAssistantAPIError.staleOperation
    }
    if persistedCredentials == nil {
      credentials = nil
      credentialGeneration += 1
      successfulRouteSourceGeneration = nil
      await publishCredentialSnapshot()
      return
    }
    guard persistedCredentials != context.credentials else {
      throw HomeAssistantAPIError.staleOperation
    }
    credentials = persistedCredentials
    credentialGeneration += 1
    authenticationSessionEpoch += 1
    rejectedCredentialGeneration = nil
    successfulRouteSourceGeneration = nil
    await publishCredentialSnapshot()
    throw HomeAssistantAPIError.staleOperation
  }

  func settleCredentialRejectionBeforeReplacement() async throws {
    guard let generation = credentialRejectionAttempt?.generation else { return }
    let waiterID = UUID()
    do {
      try await withTaskCancellationHandler {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
          addCredentialRejectionWaiter(
            id: waiterID,
            generation: generation,
            continuation: continuation
          )
        }
      } onCancel: {
        Task { await self.cancelCredentialRejectionWaiter(id: waiterID) }
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
    }
  }

  private func completeCredentialRejection(
    attemptID: UUID,
    with result: Result<Void, any Error>
  ) {
    guard let activeAttempt = credentialRejectionAttempt, activeAttempt.id == attemptID else {
      return
    }
    credentialRejectionAttempt = nil
    finishAuthenticationReplacement(operationEpoch: activeAttempt.operationEpoch)
    activeAttempt.waiters.values.forEach { $0.resume(with: result) }
  }

  private func cancelCredentialRejectionWaiter(id waiterID: UUID) {
    guard var activeAttempt = credentialRejectionAttempt,
      let continuation = activeAttempt.waiters.removeValue(forKey: waiterID)
    else {
      return
    }
    continuation.resume(throwing: CancellationError())
    credentialRejectionAttempt = activeAttempt
  }
}

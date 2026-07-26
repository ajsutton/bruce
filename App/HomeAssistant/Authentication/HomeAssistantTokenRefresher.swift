import Foundation

actor HomeAssistantTokenRefresher {
  typealias TokenResult = (HomeAssistantToken, URL)
  typealias Waiter = CheckedContinuation<TokenResult, any Error>

  private struct Attempt {
    let id: UUID
    var task: Task<Void, Never>?
    var waiters: [UUID: Waiter]
  }

  private let authenticationClient: HomeAssistantAuthenticationClient
  private let cancellationDeferral: @Sendable () async -> Void
  private let waiterRegistered: @Sendable (Int) -> Void
  private var attempt: Attempt?

  init(
    authenticationClient: HomeAssistantAuthenticationClient,
    cancellationDeferral: @escaping @Sendable () async -> Void = {},
    waiterRegistered: @escaping @Sendable (Int) -> Void = { _ in }
  ) {
    self.authenticationClient = authenticationClient
    self.cancellationDeferral = cancellationDeferral
    self.waiterRegistered = waiterRegistered
  }

  func token(
    for credentials: HomeAssistantCredentials
  ) async throws -> TokenResult {
    let waiterID = UUID()
    let result = try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        addWaiter(
          id: waiterID,
          continuation: continuation,
          credentials: credentials
        )
      }
    } onCancel: {
      Task { [cancellationDeferral] in
        await cancellationDeferral()
        await self.cancelWaiter(id: waiterID)
      }
    }
    try Task.checkCancellation()
    return result
  }

  func cancel() {
    let activeAttempt = attempt
    attempt = nil
    activeAttempt?.task?.cancel()
    activeAttempt?.waiters.values.forEach {
      $0.resume(throwing: CancellationError())
    }
  }

  private func addWaiter(
    id waiterID: UUID,
    continuation: Waiter,
    credentials: HomeAssistantCredentials
  ) {
    if attempt == nil {
      let attemptID = UUID()
      attempt = Attempt(
        id: attemptID,
        task: nil,
        waiters: [waiterID: continuation]
      )
      let task = Task { [authenticationClient] in
        let result: Result<TokenResult, any Error>
        do {
          result = .success(
            try await Self.loadToken(
              for: credentials,
              authenticationClient: authenticationClient
            )
          )
        } catch {
          result = .failure(error)
        }
        self.complete(attemptID: attemptID, with: result)
      }
      attempt?.task = task
    } else {
      attempt?.waiters[waiterID] = continuation
    }
    waiterRegistered(attempt?.waiters.count ?? 0)
  }

  private func cancelWaiter(id waiterID: UUID) {
    guard let continuation = attempt?.waiters.removeValue(forKey: waiterID) else {
      return
    }
    continuation.resume(throwing: CancellationError())
    guard attempt?.waiters.isEmpty == true else {
      return
    }
    attempt?.task?.cancel()
    attempt = nil
  }

  private func complete(
    attemptID: UUID,
    with result: Result<TokenResult, any Error>
  ) {
    guard let activeAttempt = attempt, activeAttempt.id == attemptID else {
      return
    }
    attempt = nil
    for waiter in activeAttempt.waiters.values {
      waiter.resume(with: result)
    }
  }

  private static func loadToken(
    for credentials: HomeAssistantCredentials,
    authenticationClient: HomeAssistantAuthenticationClient
  ) async throws -> TokenResult {
    let candidates = try HomeAssistantRequestRouter.candidates(for: credentials)
    var lastConnectivityError: (any Error)?
    for (index, baseURL) in candidates.enumerated() {
      do {
        let token = try await authenticationClient.refresh(
          refreshToken: credentials.refreshToken,
          at: baseURL
        )
        return (token, baseURL)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        guard
          HomeAssistantRequestRouter.isConnectivityFailure(error),
          index + 1 < candidates.count
        else {
          throw error
        }
        lastConnectivityError = error
      }
    }
    throw lastConnectivityError ?? HomeAssistantAPIError.invalidServerURL
  }
}

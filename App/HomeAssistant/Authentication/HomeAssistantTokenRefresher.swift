import Foundation

actor HomeAssistantTokenRefresher {
  typealias TokenResult = (HomeAssistantToken, URL)
  typealias Waiter = CheckedContinuation<TokenResult, any Error>

  private struct Attempt {
    let id: UUID
    let credentials: HomeAssistantCredentials
    var task: Task<Void, Never>?
    var waiters: [UUID: Waiter]
  }

  private struct RejectedRefresh {
    let identity: RefreshIdentity
    let error: any Error
  }

  private struct RefreshIdentity: Equatable {
    let accessToken: String
    let refreshToken: String
    let clientID: URL
    let internalURL: URL?
    let externalURL: URL?

    init(_ credentials: HomeAssistantCredentials) {
      accessToken = credentials.accessToken
      refreshToken = credentials.refreshToken
      clientID = credentials.clientID
      internalURL = credentials.internalURL
      externalURL = credentials.externalURL
    }
  }

  private let authenticationClient: HomeAssistantAuthenticationClient
  private let cancellationDeferral: @Sendable () async -> Void
  private let waiterRegistered: @Sendable (Int) -> Void
  private var attempt: Attempt?
  private var rejectedRefresh: RejectedRefresh?

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
    rejectedRefresh = nil
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
    if let rejectedRefresh, rejectedRefresh.identity == RefreshIdentity(credentials) {
      continuation.resume(throwing: rejectedRefresh.error)
      return
    }
    if attempt == nil {
      startAttempt(credentials: credentials, waiters: [waiterID: continuation])
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
  }

  private func complete(
    attemptID: UUID,
    with result: Result<TokenResult, any Error>
  ) {
    guard let activeAttempt = attempt, activeAttempt.id == attemptID else {
      return
    }
    attempt = nil
    if case .failure(let error) = result,
      error is CancellationError,
      !activeAttempt.waiters.isEmpty
    {
      startAttempt(
        credentials: activeAttempt.credentials,
        waiters: activeAttempt.waiters
      )
      return
    }
    if case .failure(let error) = result,
      HomeAssistantRequestRouter.isRejectedRefresh(error)
    {
      rejectedRefresh = RejectedRefresh(
        identity: RefreshIdentity(activeAttempt.credentials),
        error: error
      )
    }
    for waiter in activeAttempt.waiters.values {
      waiter.resume(with: result)
    }
  }

  private func startAttempt(
    credentials: HomeAssistantCredentials,
    waiters: [UUID: Waiter]
  ) {
    let attemptID = UUID()
    attempt = Attempt(
      id: attemptID,
      credentials: credentials,
      task: nil,
      waiters: waiters
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
  }

  private static func loadToken(
    for credentials: HomeAssistantCredentials,
    authenticationClient: HomeAssistantAuthenticationClient
  ) async throws -> TokenResult {
    let candidates = try HomeAssistantRequestRouter.candidates(for: credentials)
    guard candidates.count > 1 else {
      let baseURL = candidates[0]
      let token = try await authenticationClient.refresh(
        refreshToken: credentials.refreshToken,
        at: baseURL
      )
      return (token, baseURL)
    }
    return try await withThrowingTaskGroup(
      of: TokenRouteAttempt.self,
      returning: TokenResult.self
    ) { group in
      for (index, baseURL) in candidates.enumerated() {
        group.addTask {
          do {
            return .success(
              try await authenticationClient.refresh(
                refreshToken: credentials.refreshToken,
                at: baseURL
              ),
              baseURL
            )
          } catch {
            return .failure(index, error)
          }
        }
      }

      var failures = [(any Error)?](repeating: nil, count: candidates.count)
      for try await attempt in group {
        switch attempt {
        case .success(let token, let baseURL):
          group.cancelAll()
          try Task.checkCancellation()
          return (token, baseURL)
        case .failure(let index, let error):
          failures[index] = error
        }
      }
      try Task.checkCancellation()
      throw preferredFailure(from: failures)
    }
  }

  private static func preferredFailure(
    from failures: [(any Error)?]
  ) -> any Error {
    let errors = failures.compactMap(\.self)
    return errors.first(where: { HomeAssistantRequestRouter.isConnectivityFailure($0) })
      ?? errors.first(where: { !HomeAssistantRequestRouter.isRejectedRefresh($0) })
      ?? errors.last
      ?? HomeAssistantAPIError.invalidServerURL
  }
}

private enum TokenRouteAttempt: Sendable {
  case success(HomeAssistantToken, URL)
  case failure(Int, any Error)
}

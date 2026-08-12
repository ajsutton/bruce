import Foundation
import OSLog

@MainActor
final class HomeAssistantConnectionController: ObservableObject {
  private static let logger = Logger(
    subsystem: "net.symphonious.bruce",
    category: "HomeAssistantAuthentication"
  )

  @Published var step: HomeAssistantSetupStore.Step = .introduction {
    didSet {
      onStepChange?(step)
    }
  }
  @Published private(set) var connectedCredentials: HomeAssistantCredentials?
  @Published private(set) var connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState =
    .idle
  @Published private(set) var isDisconnecting = false

  private let connection: (any HomeAssistantConnecting)?
  private var connectionCheckDidSucceed: @MainActor @Sendable () async -> Void
  private var connectionTask: Task<Void, Never>?
  private var connectionGeneration = UUID()
  private var hasAttemptedRestore = false
  var onStepChange: ((HomeAssistantSetupStore.Step) -> Void)?

  init(
    connection: (any HomeAssistantConnecting)?,
    connectionCheckDidSucceed: @escaping @MainActor @Sendable () async -> Void
  ) {
    self.connection = connection
    self.connectionCheckDidSucceed = connectionCheckDidSucceed
  }

  deinit {
    connectionTask?.cancel()
  }

  func setConnectionCheckDidSucceed(
    _ action: @escaping @MainActor @Sendable () async -> Void
  ) {
    connectionCheckDidSucceed = action
  }

  func requestAuthentication() {
    guard case .confirmation(let candidate) = step else {
      return
    }
    step = .readyForAuthentication(candidate)
    guard let connection else {
      return
    }
    let generation = beginConnectionOperation()
    connectionTask = Task { [weak self, connection] in
      do {
        let credentials = try await connection.connect(to: candidate)
        try Task.checkCancellation()
        guard let self, self.connectionGeneration == generation else {
          return
        }
        self.connectionTask = nil
        self.connectedCredentials = credentials
        self.connectionCheckState = .succeeded
        self.step = .connected(credentials)
      } catch is CancellationError {
        guard let self, self.connectionGeneration == generation else {
          return
        }
        self.connectionTask = nil
        self.step = .confirmation(candidate)
      } catch {
        guard let self, self.connectionGeneration == generation else {
          return
        }
        let failure = HomeAssistantAuthenticationFailure(error: error)
        Self.logger.error("Authentication failed: \(failure.diagnostic, privacy: .public)")
        self.connectionTask = nil
        self.step = .authenticationFailed(candidate, failure)
      }
    }
  }

  func cancelAuthentication() {
    guard case .readyForAuthentication(let candidate) = step else {
      return
    }
    invalidateConnectionOperation()
    step = .confirmation(candidate)
  }

  func retryAuthentication() {
    guard case .authenticationFailed(let candidate, _) = step else {
      return
    }
    step = .confirmation(candidate)
    requestAuthentication()
  }

  func restoreSavedConnection() async {
    guard !hasAttemptedRestore, let connection else {
      return
    }
    hasAttemptedRestore = true
    step = .restoring
    let generation = beginConnectionOperation()
    let task = Task { [weak self, connection] in
      do {
        guard let credentials = try await connection.restore() else {
          self?.applyNoSavedConnection(generation: generation)
          return
        }
        try Task.checkCancellation()
        self?.applyRestored(credentials, generation: generation)
      } catch is CancellationError {
      } catch {
        self?.applyRestoreFailure(generation: generation)
      }
    }
    connectionTask = task
    await task.value
  }

  func testConnection() {
    guard let connection, let credentials = connectedCredentials else {
      return
    }
    let generation = beginConnectionOperation()
    connectionCheckState = .checking
    startConnectionCheck(
      connection: connection,
      credentials: credentials,
      generation: generation
    )
  }

  func changeServer() {
    invalidateConnectionOperation()
    step = .introduction
  }

  func disconnect() {
    guard !isDisconnecting else {
      return
    }
    guard let connection else {
      connectedCredentials = nil
      step = .introduction
      return
    }
    let generation = beginConnectionOperation()
    let previousStep = step
    isDisconnecting = true
    connectionCheckState = .idle
    if let connectedCredentials {
      step = .disconnecting(connectedCredentials)
    }
    connectionTask = Task { [weak self, connection] in
      do {
        try await connection.disconnect()
        try Task.checkCancellation()
        guard let self, self.connectionGeneration == generation else {
          return
        }
        self.connectionTask = nil
        self.connectedCredentials = nil
        self.connectionCheckState = .idle
        self.isDisconnecting = false
        self.step = .introduction
      } catch is CancellationError {
      } catch {
        guard let self, self.connectionGeneration == generation else {
          return
        }
        self.connectionTask = nil
        self.isDisconnecting = false
        self.connectionCheckState = .disconnectFailed
        switch previousStep {
        case .configured, .connected:
          self.step = previousStep
        case .restoring, .restoreFailed, .introduction, .chooseServer, .manualEntry, .confirmation,
          .unencryptedWarning, .onboardingRequired, .readyForAuthentication,
          .authenticationFailed, .disconnecting, .cancelled:
          break
        }
      }
    }
  }

  func cancel() {
    invalidateConnectionOperation()
    step = .cancelled
  }
}

extension HomeAssistantConnectionController {
  private func startConnectionCheck(
    connection: any HomeAssistantConnecting,
    credentials: HomeAssistantCredentials,
    generation: UUID
  ) {
    connectionTask = Task { [weak self, connection] in
      do {
        let outcome = try await HomeAssistantConnectionVerification.check(
          using: connection,
          fallback: credentials
        )
        guard
          let connectionCheckDidSucceed = self?.successfulConnectionCheckAction(
            generation: generation
          )
        else { return }
        if case .verified = outcome {
          try Task.checkCancellation()
          await connectionCheckDidSucceed()
        }
        try Task.checkCancellation()
        self?.applyConnectionCheck(outcome, generation: generation)
      } catch is CancellationError {
      } catch {
        self?.applyConfigured(credentials, state: .failed(.other), generation: generation)
      }
    }
  }

  private func successfulConnectionCheckAction(
    generation: UUID
  ) -> (@MainActor @Sendable () async -> Void)? {
    guard connectionGeneration == generation else { return nil }
    return connectionCheckDidSucceed
  }

  private func applyRestored(
    _ credentials: HomeAssistantCredentials,
    generation: UUID
  ) {
    guard connectionGeneration == generation else {
      return
    }
    connectionTask = nil
    connectedCredentials = credentials
    connectionCheckState = .idle
    step = .connected(credentials)
  }

  private func applyRestoreFailure(generation: UUID) {
    guard connectionGeneration == generation else {
      return
    }
    connectionTask = nil
    connectedCredentials = nil
    connectionCheckState = .idle
    step = .restoreFailed
  }

  private func applyConnectionCheck(
    _ outcome: HomeAssistantConnectionVerification.Outcome,
    generation: UUID
  ) {
    switch outcome {
    case .verified(let credentials):
      applyVerified(credentials, generation: generation)
    case .configured(let credentials, let state):
      applyConfigured(credentials, state: state, generation: generation)
    }
  }

  private func applyVerified(
    _ credentials: HomeAssistantCredentials,
    generation: UUID
  ) {
    guard connectionGeneration == generation else {
      return
    }
    connectionTask = nil
    connectedCredentials = credentials
    connectionCheckState = .succeeded
    step = .connected(credentials)
  }

  private func applyConfigured(
    _ credentials: HomeAssistantCredentials,
    state: HomeAssistantSetupStore.ConnectionCheckState,
    generation: UUID
  ) {
    guard connectionGeneration == generation else {
      return
    }
    connectionTask = nil
    connectedCredentials = credentials
    connectionCheckState = state
    step = state == .reauthenticationRequired ? .configured(credentials) : .connected(credentials)
  }

  private func applyNoSavedConnection(generation: UUID) {
    guard connectionGeneration == generation else {
      return
    }
    connectionTask = nil
    connectedCredentials = nil
    connectionCheckState = .idle
    step = .introduction
  }

  private func beginConnectionOperation() -> UUID {
    invalidateConnectionOperation()
    let generation = UUID()
    connectionGeneration = generation
    return generation
  }

  private func invalidateConnectionOperation() {
    connectionGeneration = UUID()
    connectionTask?.cancel()
    connectionTask = nil
    connection?.cancel()
    isDisconnecting = false
  }
}

extension HomeAssistantConnectionController {
  func requireReauthentication() {
    guard let credentials = connectedCredentials else {
      return
    }
    invalidateConnectionOperation()
    connectionCheckState = .reauthenticationRequired
    step = .configured(credentials)
  }

  func reauthenticate() {
    guard let credentials = connectedCredentials else {
      return
    }
    let candidate = HomeAssistantConnectionCandidate(
      instanceID: credentials.instanceID,
      name: credentials.instanceName,
      internalURL: credentials.internalURL,
      externalURL: credentials.externalURL,
      activeURL: credentials.lastSuccessfulURL,
      source: .manual
    )
    invalidateConnectionOperation()
    step = .confirmation(candidate)
    requestAuthentication()
  }
}

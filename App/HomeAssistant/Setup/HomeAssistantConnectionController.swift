import Foundation
import OSLog

@MainActor
final class HomeAssistantConnectionController: ObservableObject {
  enum ConnectionCheckContext {
    case setup
    case existingConnection
  }

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
  @Published var connectionCheckState: HomeAssistantSetupStore.ConnectionCheckState =
    .idle
  @Published private(set) var isDisconnecting = false

  private let connection: (any HomeAssistantConnecting)?
  private var connectionTask: Task<Void, Never>?
  private var credentialTask: Task<Void, Never>?
  private var connectionGeneration = UUID()
  private var hasAttemptedRestore = false
  var onStepChange: ((HomeAssistantSetupStore.Step) -> Void)?

  init(
    connection: (any HomeAssistantConnecting)?,
    credentialEvents: HomeAssistantCredentialEvents? = nil
  ) {
    self.connection = connection
    if let credentialEvents {
      credentialTask = Task { [weak self] in
        for await snapshot in await credentialEvents.updates() {
          guard !Task.isCancelled else { return }
          if snapshot.availability == .rejected {
            self?.requireReauthentication()
          }
        }
      }
    }
  }

  deinit {
    connectionTask?.cancel()
    credentialTask?.cancel()
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
        let credentials = try await connection.authenticate(to: candidate)
        try Task.checkCancellation()
        await self?.completeAuthentication(
          credentials,
          using: connection,
          generation: generation
        )
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
      generation: generation,
      context: .existingConnection
    )
  }

  func retryConnection() {
    guard
      case .connectionFailed(let credentials, _) = step,
      let connection
    else {
      return
    }
    let generation = beginConnectionOperation()
    connectionCheckState = .checking
    step = .finishingConnection(credentials)
    startConnectionCheck(
      connection: connection,
      credentials: credentials,
      generation: generation,
      context: .setup
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
          .authenticationFailed, .finishingConnection, .connectionFailed, .disconnecting,
          .cancelled:
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
    generation: UUID,
    context: ConnectionCheckContext
  ) {
    connectionTask = Task { [weak self, connection] in
      do {
        let outcome = try await HomeAssistantConnectionVerification.check(
          using: connection,
          fallback: credentials
        )
        try Task.checkCancellation()
        self?.applyConnectionCheck(outcome, generation: generation, context: context)
      } catch is CancellationError {
      } catch {
        self?.applyConfigured(
          credentials,
          state: .failed(.other),
          generation: generation,
          context: context
        )
      }
    }
  }

  private func completeAuthentication(
    _ credentials: HomeAssistantCredentials,
    using connection: any HomeAssistantConnecting,
    generation: UUID
  ) async {
    guard connectionGeneration == generation else {
      return
    }
    connectedCredentials = credentials
    connectionCheckState = .checking
    step = .finishingConnection(credentials)
    do {
      let outcome = try await HomeAssistantConnectionVerification.check(
        using: connection,
        fallback: credentials
      )
      try Task.checkCancellation()
      applyConnectionCheck(outcome, generation: generation, context: .setup)
    } catch is CancellationError {
    } catch {
      applyConfigured(
        credentials,
        state: .failed(.other),
        generation: generation,
        context: .setup
      )
    }
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
    generation: UUID,
    context: ConnectionCheckContext
  ) {
    switch outcome {
    case .verified(let credentials):
      applyVerified(credentials, generation: generation)
    case .configured(let credentials, let state):
      applyConfigured(credentials, state: state, generation: generation, context: context)
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
    generation: UUID,
    context: ConnectionCheckContext
  ) {
    guard connectionGeneration == generation else {
      return
    }
    connectionTask = nil
    connectedCredentials = credentials
    connectionCheckState = state
    switch (context, state) {
    case (_, .reauthenticationRequired):
      step = .configured(credentials)
    case (.setup, .failed(let problem)):
      step = .connectionFailed(credentials, problem)
    case (.setup, .idle), (.setup, .checking), (.setup, .succeeded),
      (.setup, .disconnectFailed), (.existingConnection, _):
      step = .connected(credentials)
    }
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

  func invalidateConnectionOperation() {
    connectionGeneration = UUID()
    connectionTask?.cancel()
    connectionTask = nil
    connection?.cancel()
    isDisconnecting = false
  }
}

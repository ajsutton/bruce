import Foundation
import OSLog

private enum HomeAssistantConnectionLog {
  static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.symphonious.bruce",
    category: "HomeAssistantConnection"
  )
}

extension HomeAssistantConnectionSupervisor {
  func logMilestone(_ milestone: String, startedAt: TimeInterval) {
    let duration = max(0, clock.now() - startedAt)
    let lifecycle = runningLifecycleID?.uuidString.prefix(8) ?? "none"
    let attempt = currentAttempt?.id.uuidString.prefix(8) ?? "none"
    HomeAssistantConnectionLog.logger.info(
      "milestone name=\(milestone, privacy: .public) durationSeconds=\(duration, privacy: .public) lifecycle=\(lifecycle, privacy: .public) attempt=\(attempt, privacy: .public)"
    )
  }

  func transition(
    to nextState: HomeAssistantConnectionState,
    trigger: HomeAssistantConnectionTrigger,
    error: (any Error)? = nil,
    retryDelay: Duration? = nil
  ) {
    let previousState = state
    let now = clock.now()
    let phaseDuration = max(0, now - phaseStartedAt)
    phaseStartedAt = now
    state = nextState
    let lifecycle = runningLifecycleID?.uuidString.prefix(8) ?? "none"
    let attempt = currentAttempt?.id.uuidString.prefix(8) ?? "none"
    let authenticationEpoch = credentialSnapshot?.authenticationSessionEpoch ?? -1
    let persistenceGeneration = credentialSnapshot?.persistenceGeneration ?? -1
    let route = currentAttempt?.routeCategory ?? "none"
    let errorCategory = error.map(Self.diagnosticCategory) ?? "none"
    let delay = retryDelay.map(String.init(describing:)) ?? "none"
    let accelerated = trigger == .pathHint || trigger == .wakeHint
    let lastEventAge =
      lastSuccessfulEventAt.map { String(format: "%.3f", max(0, now - $0)) }
      ?? "none"
    let classification =
      error.map { _ in
        nextState == .requiresUserAction ? "terminal" : "recoverable"
      } ?? "none"
    HomeAssistantConnectionLog.logger.info(
      "transition previous=\(String(describing: previousState), privacy: .public) next=\(String(describing: nextState), privacy: .public) trigger=\(trigger.rawValue, privacy: .public) lifecycle=\(lifecycle, privacy: .public) attempt=\(attempt, privacy: .public) authenticationEpoch=\(authenticationEpoch, privacy: .public) persistenceGeneration=\(persistenceGeneration, privacy: .public) route=\(route, privacy: .public) retryAttempt=\(self.failureCount, privacy: .public) retryDelay=\(delay, privacy: .public) accelerated=\(accelerated, privacy: .public) phaseDurationSeconds=\(phaseDuration, privacy: .public) lastEventAgeSeconds=\(lastEventAge, privacy: .public) classification=\(classification, privacy: .public) error=\(errorCategory, privacy: .public)"
    )
  }

  private static func diagnosticCategory(for error: any Error) -> String {
    guard let apiError = error as? HomeAssistantAPIError else {
      return String(reflecting: type(of: error))
    }
    return switch apiError {
    case .noCredentials: "noCredentials"
    case .invalidServerURL: "invalidServerURL"
    case .unauthorized: "unauthorized"
    case .reauthenticationRequired: "reauthenticationRequired"
    case .incompatibleServer: "incompatibleServer"
    case .server: "server"
    case .invalidResponse: "invalidResponse"
    case .staleOperation: "staleOperation"
    }
  }
}

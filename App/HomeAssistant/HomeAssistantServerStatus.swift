import Foundation

struct HomeAssistantServerStatus: Equatable {
  enum Phase: Equatable {
    case idle
    case updating
    case live
    case reconnecting
    case unavailable
    case signInRequired
    case needsAttention
  }

  let phase: Phase
  let lastSuccessfulUpdate: Date?

  static let idle = HomeAssistantServerStatus(
    phase: .idle,
    lastSuccessfulUpdate: nil
  )

  func receiving(
    _ update: HomeAssistantStateUpdate,
    at date: Date
  ) -> HomeAssistantServerStatus {
    switch update.phase {
    case .live:
      HomeAssistantServerStatus(phase: .live, lastSuccessfulUpdate: date)
    case .refreshing:
      HomeAssistantServerStatus(
        phase: .updating,
        lastSuccessfulUpdate: lastSuccessfulUpdate
      )
    case .reconnecting:
      HomeAssistantServerStatus(
        phase: .reconnecting,
        lastSuccessfulUpdate: lastSuccessfulUpdate
      )
    }
  }

  func receiving(error: any Error) -> HomeAssistantServerStatus {
    HomeAssistantServerStatus(
      phase: Self.phase(for: error),
      lastSuccessfulUpdate: lastSuccessfulUpdate
    )
  }

  private static func phase(for error: any Error) -> Phase {
    if HomeAssistantRequestRouter.isConnectivityFailure(error) {
      return .unavailable
    }
    guard let apiError = error as? HomeAssistantAPIError else {
      return .needsAttention
    }
    switch apiError {
    case .noCredentials, .unauthorized, .reauthenticationRequired:
      return .signInRequired
    case .invalidServerURL, .invalidResponse, .incompatibleServer, .server, .staleOperation:
      return .needsAttention
    }
  }
}

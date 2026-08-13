import Foundation

struct HomeAssistantServerStatus: Equatable {
  static let recentUpdateInterval: TimeInterval = 5 * 60

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

  func lastSuccessfulUpdateForDisplay(at date: Date) -> Date? {
    guard let lastSuccessfulUpdate,
      date.timeIntervalSince(lastSuccessfulUpdate) >= Self.recentUpdateInterval
    else {
      return nil
    }
    return lastSuccessfulUpdate
  }

  static func nextTimestampRefresh(
    after date: Date,
    lastSuccessfulUpdate: Date?
  ) -> Date {
    guard let lastSuccessfulUpdate else {
      return date.addingTimeInterval(60)
    }
    let freshnessBoundary = lastSuccessfulUpdate.addingTimeInterval(recentUpdateInterval)
    return freshnessBoundary > date ? freshnessBoundary : date.addingTimeInterval(60)
  }

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
    case .unavailable:
      HomeAssistantServerStatus(
        phase: update.failure == .authentication ? .signInRequired : .needsAttention,
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

import Foundation

extension HomeAssistantHomeEnergyStore {
  enum Problem: Equatable {
    case connectionNeedsManagement
    case connectionUnavailable
    case reconnecting
    case signInRequired
    case invalidResponse

    var needsConnectionManagement: Bool {
      self == .connectionNeedsManagement || self == .signInRequired
    }

    var offersRecoveryAction: Bool {
      self != .reconnecting
    }
  }

  static func problem(for error: any Error) -> Problem {
    if HomeAssistantRequestRouter.isConnectivityFailure(error) {
      return .connectionUnavailable
    }
    guard let apiError = error as? HomeAssistantAPIError else {
      return .invalidResponse
    }
    switch apiError {
    case .noCredentials, .unauthorized, .reauthenticationRequired:
      return .signInRequired
    case .invalidServerURL:
      return .connectionUnavailable
    case .invalidResponse, .incompatibleServer, .server, .staleOperation:
      return .invalidResponse
    }
  }

  static func isCancellation(_ error: any Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }
}

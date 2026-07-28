import Foundation

extension HomeAssistantEVChargingStore {
  enum Problem: Equatable {
    case connectionNeedsManagement
    case connectionUnavailable
    case reconnecting
    case signInRequired
    case invalidResponse
    case updateFailed
    case updateTimedOut

    var needsConnectionManagement: Bool {
      self == .connectionNeedsManagement || self == .signInRequired
    }

    var offersRecoveryAction: Bool {
      self != .reconnecting
    }
  }

  enum Operation {
    case loading
    case changing
  }

  static func problem(
    for error: any Error,
    operation: Operation
  ) -> Problem {
    if HomeAssistantRequestRouter.isConnectivityFailure(error) {
      return .connectionUnavailable
    }
    guard let apiError = error as? HomeAssistantAPIError else {
      return operation == .loading ? .invalidResponse : .updateFailed
    }
    switch apiError {
    case .noCredentials, .unauthorized, .reauthenticationRequired:
      return .signInRequired
    case .invalidResponse, .incompatibleServer:
      return .invalidResponse
    case .invalidServerURL:
      return .connectionUnavailable
    case .server, .staleOperation:
      return operation == .loading ? .invalidResponse : .updateFailed
    }
  }

  static func isCancellation(_ error: any Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }
}

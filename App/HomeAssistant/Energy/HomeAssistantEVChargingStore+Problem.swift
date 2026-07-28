import Foundation

extension HomeAssistantEVChargingStore {
  enum Problem: Equatable {
    case connectionNeedsManagement
    case connectionUnavailable
    case signInRequired
    case invalidResponse
    case updateFailed
    case updateTimedOut

    var message: String {
      switch self {
      case .connectionNeedsManagement:
        "The Home Assistant connection needs attention. The charging mode may be out of date."
      case .connectionUnavailable:
        "Home Assistant can’t be reached. The charging mode may be out of date."
      case .signInRequired:
        "Sign in to Home Assistant again to update the charging mode."
      case .invalidResponse:
        "Home Assistant returned a charging mode Bruce couldn’t read."
      case .updateFailed:
        "Bruce couldn’t change the charging mode."
      case .updateTimedOut:
        "Home Assistant took too long to confirm the charging mode."
      }
    }

    var needsConnectionManagement: Bool {
      self == .connectionNeedsManagement || self == .signInRequired
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

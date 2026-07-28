import Foundation

extension HomeAssistantHomeEnergyStore {
  enum Problem: Equatable {
    case connectionNeedsManagement
    case connectionUnavailable
    case signInRequired
    case invalidResponse

    var message: String {
      switch self {
      case .connectionNeedsManagement:
        "The Home Assistant connection needs attention. Power readings may be out of date."
      case .connectionUnavailable:
        "Home Assistant can’t be reached. Power readings may be out of date."
      case .signInRequired:
        "Sign in to Home Assistant again to update power readings."
      case .invalidResponse:
        "Home Assistant returned power readings Bruce couldn’t read."
      }
    }

    var needsConnectionManagement: Bool {
      self == .connectionNeedsManagement || self == .signInRequired
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

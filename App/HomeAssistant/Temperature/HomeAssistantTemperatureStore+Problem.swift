import Foundation

extension HomeAssistantTemperatureStore {
  struct ControlProblem: Equatable {
    let message: String
  }

  enum Problem: Equatable {
    case connectionUnavailable
    case reconnecting
    case signInRequired
    case invalidResponse
    case other

    var message: String {
      switch self {
      case .connectionUnavailable:
        "Home Assistant can’t be reached. Temperatures may be out of date."
      case .reconnecting:
        "Reconnecting to Home Assistant. Temperatures may be out of date."
      case .signInRequired:
        "Sign in to Home Assistant again to update temperatures."
      case .invalidResponse:
        "Home Assistant returned temperature data Bruce couldn’t read."
      case .other:
        "Bruce couldn’t update the temperatures."
      }
    }
  }

  static func problem(for error: any Error) -> Problem {
    if HomeAssistantRequestRouter.isConnectivityFailure(error) {
      return .connectionUnavailable
    }
    guard let apiError = error as? HomeAssistantAPIError else {
      return .other
    }
    switch apiError {
    case .noCredentials, .unauthorized, .reauthenticationRequired:
      return .signInRequired
    case .invalidResponse, .incompatibleServer:
      return .invalidResponse
    case .invalidServerURL:
      return .connectionUnavailable
    case .server, .staleOperation:
      return .other
    }
  }

  static func isCancellation(_ error: any Error) -> Bool {
    (error as? URLError)?.code == .cancelled
  }
}

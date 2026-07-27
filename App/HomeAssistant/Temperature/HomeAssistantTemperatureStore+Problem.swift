import Foundation

extension HomeAssistantTemperatureStore {
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

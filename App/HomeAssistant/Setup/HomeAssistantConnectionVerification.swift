import Foundation

@MainActor
enum HomeAssistantConnectionVerification {
  enum Outcome {
    case noSavedConnection
    case verified(HomeAssistantCredentials)
    case configured(
      HomeAssistantCredentials,
      HomeAssistantSetupStore.ConnectionCheckState
    )
  }

  static func check(
    using connection: any HomeAssistantConnecting,
    fallback credentials: HomeAssistantCredentials
  ) async throws -> Outcome {
    do {
      let verifiedCredentials = try await connection.testConnection()
      try Task.checkCancellation()
      return .verified(verifiedCredentials)
    } catch HomeAssistantAPIError.reauthenticationRequired,
      HomeAssistantAPIError.unauthorized,
      HomeAssistantAPIError.noCredentials
    {
      try Task.checkCancellation()
      return .configured(credentials, .reauthenticationRequired)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      return .configured(credentials, .failed(problem(for: error)))
    }
  }

  private static func problem(
    for error: any Error
  ) -> HomeAssistantSetupStore.ConnectionCheckProblem {
    if HomeAssistantRequestRouter.isConnectivityFailure(error) {
      return .networkUnavailable
    }
    if case .serverRejectedRequest = error as? HomeAssistantAuthenticationError {
      return .serverRejectedRequest
    }
    guard let apiError = error as? HomeAssistantAPIError else {
      return .other
    }
    switch apiError {
    case .incompatibleServer:
      return .incompatibleServer
    case .server:
      return .serverRejectedRequest
    case .invalidResponse:
      return .invalidResponse
    case .invalidServerURL:
      return .networkUnavailable
    case .noCredentials, .unauthorized, .reauthenticationRequired:
      return .other
    case .staleOperation:
      return .other
    }
  }
}

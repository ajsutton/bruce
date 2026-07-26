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

  static func restore(
    using connection: any HomeAssistantConnecting
  ) async throws -> Outcome {
    guard let credentials = try await connection.restore() else {
      return .noSavedConnection
    }
    try Task.checkCancellation()
    return try await check(using: connection, fallback: credentials)
  }

  static func check(
    using connection: any HomeAssistantConnecting,
    fallback credentials: HomeAssistantCredentials
  ) async throws -> Outcome {
    do {
      let verifiedCredentials = try await connection.testConnection()
      try Task.checkCancellation()
      return .verified(verifiedCredentials)
    } catch HomeAssistantAPIError.reauthenticationRequired {
      return .configured(credentials, .reauthenticationRequired)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return .configured(credentials, .failed)
    }
  }
}

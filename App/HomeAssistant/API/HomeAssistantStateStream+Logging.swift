import Foundation
import OSLog

private enum HomeAssistantStateStreamLog {
  static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.symphonious.bruce",
    category: "HomeAssistantStateSubscription"
  )
}

extension HomeAssistantStateStream {
  static func reportDisconnect(
    _ error: any Error,
    update: HomeAssistantStateUpdate,
    to continuation: HomeAssistantBufferedUpdateStream<
      HomeAssistantStateUpdate
    >.Continuation
  ) {
    HomeAssistantStateStreamLog.logger.error(
      "Home Assistant state subscription disconnected [\(diagnosticCategory(for: error), privacy: .public)]: \(String(describing: error), privacy: .private)"
    )
    yield(update, to: continuation)
  }

  static func reportTerminalDisconnect(_ error: any Error) {
    HomeAssistantStateStreamLog.logger.error(
      "Home Assistant state subscription stopped reconnecting [\(diagnosticCategory(for: error), privacy: .public)]: \(String(describing: error), privacy: .private)"
    )
  }

  private static func diagnosticCategory(for error: any Error) -> String {
    guard let apiError = error as? HomeAssistantAPIError else {
      return String(reflecting: type(of: error))
    }
    return switch apiError {
    case .noCredentials: "noCredentials"
    case .invalidServerURL: "invalidServerURL"
    case .unauthorized: "unauthorized"
    case .reauthenticationRequired: "reauthenticationRequired"
    case .incompatibleServer: "incompatibleServer"
    case .server: "server"
    case .invalidResponse: "invalidResponse"
    case .staleOperation: "staleOperation"
    }
  }
}

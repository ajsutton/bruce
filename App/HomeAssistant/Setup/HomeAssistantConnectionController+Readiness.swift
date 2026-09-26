import Foundation

extension HomeAssistantConnectionController {
  /// A restored session is usable only while the selected connection remains configured.
  func checkRestoredConnection(_ outcome: HomeAssistantRestoreWaiters.Outcome) throws {
    try Task.checkCancellation()
    guard outcome == .finished else { throw HomeAssistantAPIError.staleOperation }
    switch step {
    case .connected, .configured, .connectionFailed:
      return
    case .restoreFailed:
      if let restoreError { throw restoreError }
      throw HomeAssistantAPIError.invalidResponse
    case .restoring, .finishingConnection, .disconnecting:
      throw HomeAssistantAPIError.staleOperation
    case .introduction, .chooseServer, .manualEntry, .confirmation, .unencryptedWarning,
      .onboardingRequired, .readyForAuthentication, .authenticationFailed, .cancelled:
      throw HomeAssistantAPIError.noCredentials
    }
  }
}

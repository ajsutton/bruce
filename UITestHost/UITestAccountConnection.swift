import Foundation

@MainActor
final class UITestAccountConnection: HomeAssistantConnecting, HomeAssistantDiscovering {
  func restore() async throws -> HomeAssistantCredentials? {
    HomeAssistantCredentials(
      instanceID: "ui-test-home", instanceName: "Test Home",
      internalURL: URL(string: "http://home.example.invalid:8123"), externalURL: nil,
      lastSuccessfulURL: URL(string: "http://home.example.invalid:8123")
        ?? URL(fileURLWithPath: "/"),
      accessToken: "ui-test-access", refreshToken: "ui-test-refresh", tokenType: "Bearer",
      accessTokenExpiresAt: Date.distantFuture,
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }

  func authenticate(to candidate: HomeAssistantConnectionCandidate) async throws
    -> HomeAssistantCredentials
  {
    throw HomeAssistantAPIError.noCredentials
  }

  func testConnection() async throws -> HomeAssistantCredentials {
    throw HomeAssistantAPIError.noCredentials
  }

  func disconnect() async throws {}
  func cancel() {}

  nonisolated func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream { $0.finish() }
  }
}

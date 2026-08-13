import Foundation

@testable import Bruce

final class SupervisorFixture: @unchecked Sendable {
  let credentialEvents = HomeAssistantCredentialEvents()
  let store = InMemoryHomeAssistantCredentialStore()
  let authenticationLoader = QueueHomeAssistantLoader()
  let apiLoader = QueueHomeAssistantLoader()
  let now = Date(timeIntervalSince1970: 20_000)
  let session: HomeAssistantSession
  private let externalURL: URL?

  init(
    snapshotValues: [Double],
    loader: (any HomeAssistantHTTPDataLoading)? = nil,
    externalURL: URL? = nil
  ) {
    self.externalURL = externalURL
    apiLoader.results = snapshotValues.map {
      .success(temperatureStates(value: $0), statusCode: 200)
    }
    session = HomeAssistantSession(
      credentialStore: store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: authenticationLoader,
        now: { Date(timeIntervalSince1970: 20_000) }
      ),
      loader: loader ?? apiLoader,
      now: { Date(timeIntervalSince1970: 20_000) },
      credentialEvents: credentialEvents
    )
  }

  func install() async throws {
    try await session.install(credentials)
  }

  var credentials: HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: externalURL,
      lastSuccessfulURL: URL(string: "http://home.local:8123") ?? URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: now.addingTimeInterval(3_600),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }

  func makeSupervisor(
    connector: ScriptedHomeAssistantConnector,
    clock: HomeAssistantConnectionClock = HomeAssistantConnectionClock(),
    phaseDeadline: Duration = .seconds(30)
  ) -> HomeAssistantConnectionSupervisor {
    HomeAssistantConnectionSupervisor(
      session: session,
      connector: connector,
      credentialEvents: credentialEvents,
      retryPolicy: HomeAssistantConnectionRetryPolicy(
        initialWindow: 0,
        maximumWindow: 0,
        randomUnit: { 0 }
      ),
      clock: clock,
      phaseDeadline: phaseDeadline
    )
  }
}

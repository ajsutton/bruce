import Foundation
import XCTest

@testable import Bruce

final class WebSocketAuthenticationRecoveryTests: XCTestCase {
  func testRejectedAuthenticationRefreshesTokenAndReconnects() async throws {
    let fixture = SessionFixture()
    let session = try await makeSession(fixture: fixture)
    let rejectedConnection = TemperatureSubscriptionConnection(
      messages: [
        .success(#"{"type":"auth_required"}"#),
        .success(#"{"type":"auth_invalid"}"#),
      ]
    )
    let recoveredConnection = authenticatedConnection()
    let connector = TemperatureSubscriptionConnector(
      connections: [rejectedConnection, recoveredConnection]
    )
    let client = HomeAssistantTemperatureStream(
      session: session,
      apiClient: HomeAssistantAPIClient(
        session: session,
        climateMetadataLoader: TemperatureSubscriptionMetadataLoader(metadata: [:])
      ),
      connector: connector,
      retryDelays: [.zero]
    )
    let probe = AsyncThrowingStreamTestProbe(client.temperatureUpdates())

    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let reconnecting = try probe.value(at: 0)
    let recovered = try snapshot(from: probe.value(at: 1))
    recoveredConnection.cancel()

    XCTAssertEqual(reconnecting, .reconnecting([]))
    XCTAssertEqual(recovered.map(\.value), [23])
    XCTAssertEqual(
      rejectedConnection.sentMessageJSON.first?["access_token"] as? String,
      "access-value"
    )
    XCTAssertEqual(
      recoveredConnection.sentMessageJSON.first?["access_token"] as? String,
      "refreshed-access"
    )
    XCTAssertEqual(fixture.authenticationLoader.requests.count, 1)
    XCTAssertEqual(
      connector.connectedURLs.map(\.absoluteString),
      [
        "ws://home.local:8123/api/websocket",
        "ws://home.local:8123/api/websocket",
      ]
    )
  }
}

private func makeSession(fixture: SessionFixture) async throws -> HomeAssistantSession {
  let tokenResponse = Data(
    #"{"access_token":"refreshed-access","token_type":"Bearer","expires_in":1800}"#.utf8
  )
  let session = fixture.makeSession(
    apiResponses: temperatureResponses(values: [23]),
    authenticationResponses: [.success(tokenResponse, statusCode: 200)]
  )
  try await session.install(internalOnlyCredentials(fixture: fixture))
  return session
}

private func internalOnlyCredentials(
  fixture: SessionFixture
) -> HomeAssistantCredentials {
  HomeAssistantCredentials(
    instanceID: "instance",
    instanceName: "Home",
    internalURL: fixture.internalURL,
    externalURL: nil,
    lastSuccessfulURL: fixture.internalURL,
    accessToken: "access-value",
    refreshToken: "refresh-value",
    tokenType: "Bearer",
    accessTokenExpiresAt: fixture.future,
    clientID: HomeAssistantOAuthConfiguration.release.clientID
  )
}

private func authenticatedConnection() -> TemperatureSubscriptionConnection {
  TemperatureSubscriptionConnection(
    messages: [
      .success(#"{"type":"auth_required"}"#),
      .success(#"{"type":"auth_ok"}"#),
      .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
    ]
  )
}

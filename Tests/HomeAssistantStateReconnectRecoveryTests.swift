import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantStateReconnectRecoveryTests: XCTestCase {
  func testHeartbeatFailureReplacesHalfOpenConnection() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(temperatureStates(value: 21), statusCode: 200),
        .success(temperatureStates(value: 23), statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())
    let halfOpenConnection = recoveryAuthenticatedConnection(
      pingError: URLError(.networkConnectionLost)
    )
    let recoveredConnection = recoveryAuthenticatedConnection()
    let heartbeat = RecordingSubscriptionSleeper(blocks: true)
    heartbeat.started.assertForOverFulfill = false
    let source = HomeAssistantStateStream(
      session: session,
      connector: TemperatureSubscriptionConnector(
        connections: [halfOpenConnection, recoveredConnection]
      ),
      retryDelays: [.zero],
      heartbeatInterval: .seconds(30),
      heartbeatSleep: heartbeat.sleep
    )
    let probe = AsyncThrowingStreamTestProbe(await source.stateUpdates())
    await fulfillment(of: [probe.received(at: 0), heartbeat.started], timeout: 1)

    heartbeat.resume()
    await fulfillment(
      of: [halfOpenConnection.pingStarted, probe.received(at: 2)],
      timeout: 1
    )
    let reconnecting = try probe.value(at: 1)
    let recovered = try probe.value(at: 2)
    recoveredConnection.cancel()
    heartbeat.cancel()

    XCTAssertEqual(reconnecting.phase, .reconnecting)
    XCTAssertEqual(recovered.phase, .live)
    XCTAssertEqual(try temperatureValue(from: recovered), 23)
  }

  func testTokenRefreshConnectivityFailureBeforeFirstConnectionRetries() async throws {
    let fixture = SessionFixture()
    let token = Data(
      #"{"access_token":"refreshed-access","token_type":"Bearer","expires_in":1800}"#.utf8
    )
    let session = fixture.makeSession(
      apiResponses: [.success(temperatureStates(value: 23), statusCode: 200)],
      authenticationResponses: [
        .failure(URLError(.notConnectedToInternet)),
        .failure(URLError(.notConnectedToInternet)),
        .success(token, statusCode: 200),
        .success(token, statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials(expiresAt: fixture.past))
    let connection = recoveryAuthenticatedConnection()
    let source = HomeAssistantStateStream(
      session: session,
      connector: TemperatureSubscriptionConnector(connections: [connection]),
      retryDelays: [.zero]
    )
    let probe = AsyncThrowingStreamTestProbe(await source.stateUpdates())

    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let reconnecting = try probe.value(at: 0)
    let recovered = try probe.value(at: 1)
    connection.cancel()

    XCTAssertEqual(reconnecting.phase, .reconnecting)
    XCTAssertTrue(reconnecting.states.isEmpty)
    XCTAssertEqual(recovered.phase, .live)
    XCTAssertEqual(try temperatureValue(from: recovered), 23)
  }

  func testInvalidResponseFromPreviouslyLiveConnectionReconnects() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .success(temperatureStates(value: 21), statusCode: 200),
        .success(temperatureStates(value: 23), statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())
    let firstConnection = recoveryAuthenticatedConnection(
      endingWith: HomeAssistantAPIError.invalidResponse
    )
    let secondConnection = recoveryAuthenticatedConnection()
    let source = HomeAssistantStateStream(
      session: session,
      connector: TemperatureSubscriptionConnector(
        connections: [firstConnection, secondConnection]
      ),
      retryDelays: [.zero]
    )
    let probe = AsyncThrowingStreamTestProbe(await source.stateUpdates())

    await fulfillment(of: [probe.received(at: 2)], timeout: 1)
    let initial = try probe.value(at: 0)
    let reconnecting = try probe.value(at: 1)
    let reconnected = try probe.value(at: 2)
    secondConnection.cancel()

    XCTAssertEqual(initial.phase, .live)
    XCTAssertEqual(try temperatureValue(from: initial), 21)
    XCTAssertEqual(reconnecting.phase, .reconnecting)
    XCTAssertEqual(try temperatureValue(from: reconnecting), 21)
    XCTAssertEqual(reconnected.phase, .live)
    XCTAssertEqual(try temperatureValue(from: reconnected), 23)
  }

  func testRouteChangeDuringAuthenticationReconnectsWithCurrentAccess() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(
      apiResponses: [
        .failure(URLError(.cannotConnectToHost)),
        .success(Data("{}".utf8), statusCode: 200),
        .success(temperatureStates(value: 23), statusCode: 200),
      ]
    )
    try await session.install(fixture.credentials())
    let staleConnection = TemperatureSubscriptionConnection(
      messages: [.success(#"{"type":"auth_required"}"#)]
    )
    let recoveredConnection = recoveryAuthenticatedConnection()
    let connector = TemperatureSubscriptionConnector(
      connections: [staleConnection, recoveredConnection]
    )
    let source = HomeAssistantStateStream(
      session: session,
      connector: connector,
      retryDelays: [.zero]
    )
    let probe = AsyncThrowingStreamTestProbe(await source.stateUpdates())
    await fulfillment(of: [staleConnection.blockedReceiveStarted], timeout: 1)

    _ = try await session.authenticatedGET(path: "api/route-switch")
    staleConnection.succeed(with: #"{"type":"auth_ok"}"#)
    staleConnection.succeed(
      with: #"{"id":1,"type":"result","success":true,"result":null}"#
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let reconnecting = try probe.value(at: 0)
    let reconnected = try probe.value(at: 1)
    recoveredConnection.cancel()

    XCTAssertEqual(reconnecting.phase, .reconnecting)
    XCTAssertTrue(reconnecting.states.isEmpty)
    XCTAssertEqual(reconnected.phase, .live)
    XCTAssertEqual(try temperatureValue(from: reconnected), 23)
    XCTAssertEqual(
      connector.connectedURLs.map(\.absoluteString),
      [
        "ws://home.local:8123/api/websocket",
        "wss://home.example/api/websocket",
      ]
    )
  }

  func testTokenRefreshDuringAuthenticationReconnectsOnSameRoute() async throws {
    let fixture = SessionFixture()
    let token = Data(
      #"{"access_token":"refreshed-access","token_type":"Bearer","expires_in":1800}"#.utf8
    )
    let session = tokenRefreshSession(fixture: fixture, token: token)
    try await session.install(fixture.credentials())
    let staleConnection = TemperatureSubscriptionConnection(
      messages: [.success(#"{"type":"auth_required"}"#)]
    )
    let recoveredConnection = recoveryAuthenticatedConnection()
    let connector = TemperatureSubscriptionConnector(
      connections: [staleConnection, recoveredConnection]
    )
    let source = HomeAssistantStateStream(
      session: session,
      connector: connector,
      retryDelays: [.zero]
    )
    let probe = AsyncThrowingStreamTestProbe(await source.stateUpdates())
    await fulfillment(of: [staleConnection.blockedReceiveStarted], timeout: 1)

    try await session.refreshIfNeeded(force: true)
    staleConnection.succeed(with: #"{"type":"auth_ok"}"#)
    staleConnection.succeed(
      with: #"{"id":1,"type":"result","success":true,"result":null}"#
    )
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let reconnecting = try probe.value(at: 0)
    let reconnected = try probe.value(at: 1)
    recoveredConnection.cancel()

    XCTAssertEqual(reconnecting.phase, .reconnecting)
    XCTAssertEqual(reconnected.phase, .live)
    XCTAssertEqual(try temperatureValue(from: reconnected), 23)
    XCTAssertEqual(
      connector.connectedURLs.map(\.absoluteString),
      [
        "ws://home.local:8123/api/websocket",
        "ws://home.local:8123/api/websocket",
      ]
    )
  }

  func testAuthenticationReplacementStopsWithoutPublishingReconnect() async throws {
    let fixture = SessionFixture()
    let loader = BlockingHomeAssistantLoader(honorsCancellation: false)
    let now = fixture.now
    let session = HomeAssistantSession(
      credentialStore: fixture.store,
      authenticationClient: HomeAssistantAuthenticationClient(
        loader: fixture.authenticationLoader,
        now: { now }
      ),
      loader: loader,
      now: { now }
    )
    let credentials = fixture.credentials()
    try await session.install(credentials)
    let connection = recoveryAuthenticatedConnection()
    let connector = TemperatureSubscriptionConnector(connections: [connection])
    let sleeper = RecordingSubscriptionSleeper(blocks: true)
    let source = HomeAssistantStateStream(
      session: session,
      connector: connector,
      retryDelays: [.seconds(30)],
      sleep: sleeper.sleep
    )
    let probe = AsyncThrowingStreamTestProbe(await source.stateUpdates())
    await fulfillment(of: [loader.started], timeout: 1)

    try await session.install(replacementCredentials(from: credentials))
    loader.succeed(with: temperatureStates(value: 23), statusCode: 200)
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    defer {
      sleeper.cancel()
      connection.cancel()
    }

    do {
      _ = try probe.value(at: 0)
      XCTFail("Expected the replaced authentication session to stop the stream.")
    } catch HomeAssistantAPIError.staleOperation {
    } catch {
      XCTFail("Unexpected authentication replacement error: \(error)")
    }
    XCTAssertEqual(connector.connectedURLs.count, 1)
  }
}

private func recoveryAuthenticatedConnection(
  endingWith error: (any Error)? = nil,
  pingError: (any Error)? = nil
) -> TemperatureSubscriptionConnection {
  var messages: [TemperatureSubscriptionConnection.Message] = [
    .success(#"{"type":"auth_required"}"#),
    .success(#"{"type":"auth_ok"}"#),
    .success(#"{"id":1,"type":"result","success":true,"result":null}"#),
  ]
  if let error {
    messages.append(.failure(error))
  }
  return TemperatureSubscriptionConnection(messages: messages, pingError: pingError)
}

private func temperatureValue(from update: HomeAssistantStateUpdate) throws -> Double {
  let state = try XCTUnwrap(update.states.first)
  return try XCTUnwrap(
    state.temperatureReading(unit: "°C", metadata: nil)?.value
  )
}

private func replacementCredentials(
  from credentials: HomeAssistantCredentials
) -> HomeAssistantCredentials {
  HomeAssistantCredentials(
    instanceID: "replacement-instance",
    instanceName: "Replacement Home",
    internalURL: credentials.internalURL,
    externalURL: credentials.externalURL,
    lastSuccessfulURL: credentials.lastSuccessfulURL,
    accessToken: credentials.accessToken,
    refreshToken: credentials.refreshToken,
    tokenType: credentials.tokenType,
    accessTokenExpiresAt: credentials.accessTokenExpiresAt,
    clientID: credentials.clientID
  )
}

private struct InternalRouteTokenLoader: HomeAssistantHTTPDataLoading {
  let token: Data

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    guard request.url?.host == "home.local" else {
      throw URLError(.cannotConnectToHost)
    }
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return (token, response)
  }
}

private func tokenRefreshSession(
  fixture: SessionFixture,
  token: Data
) -> HomeAssistantSession {
  fixture.apiLoader.results = [
    .success(temperatureStates(value: 23), statusCode: 200)
  ]
  let now = fixture.now
  return HomeAssistantSession(
    credentialStore: fixture.store,
    authenticationClient: HomeAssistantAuthenticationClient(
      loader: InternalRouteTokenLoader(token: token),
      now: { now }
    ),
    loader: fixture.apiLoader,
    now: { now }
  )
}

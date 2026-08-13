import XCTest

@testable import Bruce

final class ConnectionSupervisorRouteTests: XCTestCase {
  func testTerminalPreferredRouteFailureFallsBackToAlternateRoute() async throws {
    let fixture = SupervisorFixture(snapshotValues: [24], externalURL: homeExternalURL)
    try await fixture.install()
    let rejected = ScriptedHomeAssistantConnection(authenticationResponse: "unexpected")
    let alternate = ScriptedHomeAssistantConnection()
    let connector = ScriptedHomeAssistantConnector(connections: [rejected, alternate])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())

    await fulfillment(of: [probe.received(at: 1)], timeout: 5)
    let recovered = try probe.value(at: 1)
    await probe.cancel()

    XCTAssertEqual(recovered.phase, .live)
    XCTAssertEqual(recovered.states.first?.state, "cool")
    XCTAssertEqual(connector.connectedURLs.map(\.absoluteString), expectedURLs)
  }

  func testTerminalFailureAfterEveryRoutePublishesUnavailableWithoutLooping() async throws {
    let fixture = SupervisorFixture(snapshotValues: [], externalURL: homeExternalURL)
    try await fixture.install()
    let preferred = ScriptedHomeAssistantConnection(authenticationResponse: "unexpected")
    let alternate = ScriptedHomeAssistantConnection(authenticationResponse: "unexpected")
    let connector = ScriptedHomeAssistantConnector(connections: [preferred, alternate])
    let supervisor = fixture.makeSupervisor(connector: connector)
    let probe = AsyncThrowingStreamTestProbe(await supervisor.stateUpdates())

    await fulfillment(of: [probe.received(at: 1)], timeout: 5)
    let unavailable = try probe.value(at: 1)
    let state = await supervisor.state
    await probe.cancel()

    XCTAssertEqual(unavailable.phase, .unavailable)
    XCTAssertEqual(state, .requiresUserAction)
    XCTAssertEqual(connector.connectionCount, 2)
    XCTAssertEqual(connector.connectedURLs.map(\.absoluteString), expectedURLs)
  }

  private var homeExternalURL: URL? { URL(string: "https://home.example") }
  private var expectedURLs: [String] {
    ["ws://home.local:8123/api/websocket", "wss://home.example/api/websocket"]
  }
}
